import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import {onSchedule} from "firebase-functions/v2/scheduler"; // 新增這行 import
admin.initializeApp();

export const sendNotification = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "必須登入才能發送通知");
  }
  const fcmToken = request.data.fcmToken;
  const title = request.data.title;
  const body = request.data.body;
  const notificationData = request.data.data || {};

  if (!fcmToken || !title || !body) {
    throw new HttpsError("invalid-argument", "缺少必要參數：fcmToken、title、body");
  }

  const message: admin.messaging.Message = {
    token: fcmToken,
    notification: {title, body},
    data: notificationData,
    android: {priority: "high"},
    apns: {payload: {aps: {badge: 1, sound: "default"}}},
  };

  try {
    await admin.messaging().send(message);
    return {success: true, message: "通知發送成功"};
  } catch (e: unknown) {
    console.error("發送通知失敗:", e);
    throw new HttpsError("internal", `發送通知失敗: ${e}`);
  }
});

// 每日配對更新 function
export const dailyMatchUpdate = onSchedule(
  {
    schedule: "0 4 * * *", // 每天台灣時間 04:00 觸發
    timeZone: "Asia/Taipei",
    memory: "1GiB", // 1GiB 記憶體，足夠存放數萬名使用者的資料快取
    timeoutSeconds: 540, // 9 分鐘超時設定，允許處理大量數據
  },
  async (_event) => {
    const db = admin.firestore();
    const now = new Date();

    // 設定日期格式 (用來產生 document ID)
    const formatter = new Intl.DateTimeFormat("en-CA", {
      timeZone: "Asia/Taipei",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    });
    const taipeiDateStr = formatter.format(now); // YYYY-MM-DD
    const todayKey = taipeiDateStr.replace(/-/g, ""); // YYYYMMDD

    try {
      console.log(`[${todayKey}] 開始執行每日配對更新...`);

      // =================================================================
      // 步驟 1: 建立全域快取 (Global Cache)
      // 一次讀取所有用戶，大幅節省讀取次數 (Cost Optimization)
      // =================================================================
      console.log("正在載入所有用戶資料至記憶體...");
      const usersSnapshot = await db.collection("users").get();
      const allUserDocs = usersSnapshot.docs;

      console.log(`共載入 ${allUserDocs.length} 位用戶資料。`);

      // 建立快速查詢表 (Lookup Maps)
      // userDataMap: 透過 ID 快速拿資料
      // userDocMap: 透過 ID 快速拿 Snapshot 物件 (有些 legacy code 可能需要 Snapshot)
      const userDataMap = new Map<string, admin.firestore.DocumentData>();
      const userDocMap = new Map<string, admin.firestore.DocumentSnapshot>();

      allUserDocs.forEach((doc) => {
        userDataMap.set(doc.id, doc.data());
        userDocMap.set(doc.id, doc);
      });

      // =================================================================
      // 步驟 2: 分批處理 (Batch Processing)
      // 避免同時發出數千個請求導致 DEADLINE_EXCEEDED
      // =================================================================
      const CHUNK_SIZE = 50; // 每批處理 50 人
      const chunks = [];
      for (let i = 0; i < allUserDocs.length; i += CHUNK_SIZE) {
        chunks.push(allUserDocs.slice(i, i + CHUNK_SIZE));
      }

      // 使用序列迴圈處理每一批 (Batch by Batch)
      for (const [chunkIndex, chunk] of chunks.entries()) {
        console.log(
          `正在處理第 ${chunkIndex + 1} / ${chunks.length} 批 ` +
          `(本批 ${chunk.length} 人)...`
        );

        // 在批次內部使用 Promise.all 進行平行處理
        const chunkPromises = chunk.map(async (userDoc) => {
          const userId = userDoc.id;
          const userData = userDoc.data();

          // 如果用戶資料損毀或為空，跳過
          if (!userData) return;

          let leftMatches = 25; // 目標配對數量
          const dailyMatchIds = new Set<string>();
          let existingUsers: admin.firestore.DocumentSnapshot[] = [];

          // -----------------------------------------------------------
          // A. 檢查今日配對快取 (Cache Check)
          // -----------------------------------------------------------
          const matchDocRef = db.collection("users")
            .doc(userId)
            .collection("dailyMatches")
            .doc(todayKey);

          const matchDoc = await matchDocRef.get();

          if (matchDoc.exists) {
            const data = matchDoc.data() || {};
            const cachedUserIds = data.userIds || [];

            // 載入既有的配對 ID
            cachedUserIds.forEach((id: string) => dailyMatchIds.add(id));
            leftMatches = 25 - cachedUserIds.length;

            if (cachedUserIds.length > 0) {
              // 直接從記憶體 (Map) 拿資料，不讀資料庫
              existingUsers = cachedUserIds
                .map((id: string) => userDocMap.get(id))
                .filter(
                  (doc: admin.firestore.DocumentSnapshot | undefined) =>
                    doc !== undefined
                ) as admin.firestore.DocumentSnapshot[];
            }
          }

          // 如果已經滿了，直接結束 (Early Return)
          if (leftMatches <= 0) {
            const recommendedUserIds = existingUsers.map((doc) => doc.id);

            // ✅ 安全寫入修正：
            // 1. 使用 { merge: true } 保護其他欄位
            // 2. 拿掉 currentMatchIdx，避免使用者閱讀進度被重置
            await matchDocRef.set({
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
              userIds: recommendedUserIds,
            }, {merge: true});

            return;
          }

          // -----------------------------------------------------------
          // B. 讀取個人私有資料 (Pushed & Likes)
          // 這是少數無法避免的讀取，因為它是 subcollection
          // -----------------------------------------------------------

          // 1. 讀取已推播名單
          const pushedSnapshot = await db.collection("users")
            .doc(userId)
            .collection("pushed")
            .get();
          const pushedIds = new Set(pushedSnapshot.docs.map((doc) => doc.id));

          // 2. 讀取按我讚的人
          const likedMeSnapshot = await db.collection("likes")
            .where("to", "==", userId)
            .get();
          const likedMeSourceIds = new Set(
            likedMeSnapshot.docs.map((doc) => doc.data().from)
          );

          // -----------------------------------------------------------
          // C. 準備配對條件
          // -----------------------------------------------------------
          const currentUserSchool = userData.school || "";
          const currentUserGender = userData.gender;
          const currentUserDepartment = userData.department || "";
          const matchSameDepartment = userData.matchSameDepartment || false;
          const matchGender: string[] = userData.matchGender || [];
          const matchSchools: string[] = userData.matchSchools || [];

          // 興趣與標籤
          const likedTagCount = userData.likedTagCount || {};
          const likedHabitCount = userData.likedHabitCount || {};

          // 計算 Top 3
          const topTags = Object.keys(likedTagCount)
            .sort((a, b) => likedTagCount[b] - likedTagCount[a])
            .slice(0, 3);
          const topHabits = Object.keys(likedHabitCount)
            .sort((a, b) => likedHabitCount[b] - likedHabitCount[a])
            .slice(0, 3);

          // -----------------------------------------------------------
          // D. 篩選：對我按讚的人 (使用記憶體 Map)
          // -----------------------------------------------------------
          let likedMeUsers: admin.firestore.DocumentSnapshot[] = [];
          if (likedMeSourceIds.size > 0) {
            likedMeUsers = Array.from(likedMeSourceIds)
              .map((id) => userDocMap.get(id)) // 從快取拿 DocumentSnapshot
              .filter((doc): doc is admin.firestore.DocumentSnapshot => {
                if (!doc) return false;
                const d = doc.data();
                if (!d) return false;

                // 檢查是否符合基本配對門檻
                return (
                  matchGender.includes(d.gender) &&
                  !pushedIds.has(doc.id) &&
                  doc.id !== userId &&
                  !dailyMatchIds.has(doc.id)
                );
              })
              .slice(0, Math.min(5, leftMatches));

            leftMatches = Math.max(0, leftMatches - likedMeUsers.length);
          }

          // -----------------------------------------------------------
          // E. 核心篩選：尋找候選人 (In-Memory Filtering)
          // ⚠️ 這是省下大量讀取的關鍵步驟，不再 query DB
          // -----------------------------------------------------------
          let candidates: admin.firestore.QueryDocumentSnapshot[] = [];

          if (matchGender.length > 0 && matchSchools.length > 0) {
            // 使用 Array.filter 取代 Firestore Query
            candidates = allUserDocs.filter((doc) => {
              const targetId = doc.id;
              const targetData = doc.data();

              // 1. 排除自己、已推播、已存在今日名單
              if (targetId === userId) return false;
              if (pushedIds.has(targetId)) return false;
              if (dailyMatchIds.has(targetId)) return false;

              // 2. 排除已經在 likedMeUsers 列表中的人 (避免重複)
              if (likedMeUsers.some((u) => u.id === targetId)) return false;

              // 3. 符合我的篩選條件 (性別、學校)
              if (!matchGender.includes(targetData.gender)) return false;
              if (!matchSchools.includes(targetData.school)) return false;

              // 4. 同系所邏輯檢查
              const isSameSchool = targetData.school === currentUserSchool;
              const isSameDepartment =
                targetData.department === currentUserDepartment;

              // 如果我不接受同系，且對方跟我同校同系 -> 排除
              if (matchSameDepartment === false &&
                  isSameSchool && isSameDepartment) {
                return false;
              }

              // 5. 【雙向配對】檢查對方是否也接受我
              const targetMatchGender = targetData.matchGender || [];
              if (!targetMatchGender.includes(currentUserGender)) return false;

              const targetMatchSchools = targetData.matchSchools || [];
              if (!targetMatchSchools.includes(currentUserSchool)) return false;

              const targetMatchSameDepartment =
                targetData.matchSameDepartment || false;
              // 如果對方不接受同系，且我跟對方同校同系 -> 排除
              if (targetMatchSameDepartment === false &&
                  isSameSchool && isSameDepartment) {
                return false;
              }

              return true;
            });
          }

          // -----------------------------------------------------------
          // F. 進階篩選：Tag & Habit
          // -----------------------------------------------------------
          const filteredUsers = candidates
            .filter((doc) => {
              const d = doc.data();
              const tags = d.tags || [];
              const habits = d.habits || [];

              const hasMatchingTag = tags.some(
                (t: string) => topTags.includes(t)
              );
              const hasMatchingHabit = habits.some(
                (h: string) => topHabits.includes(h)
              );

              return hasMatchingTag || hasMatchingHabit;
            })
            .slice(0, Math.min(15, leftMatches));

          leftMatches = Math.max(0, leftMatches - filteredUsers.length);

          // -----------------------------------------------------------
          // G. 隨機補滿
          // -----------------------------------------------------------
          // 建立已選名單 ID Set 以加速排除
          const chosenIds = new Set(filteredUsers.map((u) => u.id));

          const remainingCandidates = candidates.filter(
            (doc) => !chosenIds.has(doc.id)
          );

          // 隨機打亂
          remainingCandidates.sort(() => Math.random() - 0.5);

          const randomSelection = remainingCandidates.slice(0, leftMatches);

          // -----------------------------------------------------------
          // H. 合併與寫入結果
          // -----------------------------------------------------------
          const finalRecommendationDocs = [
            ...existingUsers, // 既有的 (排最前)
            ...likedMeUsers, // 按讚的
            ...filteredUsers, // 興趣相投的
            ...randomSelection, // 隨機的
          ].slice(0, 25);

          const finalUserIds = finalRecommendationDocs.map((doc) => doc.id);

          // ✅ 安全寫入修正：
          // 這裡是產生新名單，可以設定 currentMatchIdx 為 0
          // 但仍建議保留 { merge: true } 以防萬一
          await matchDocRef.set({
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            userIds: finalUserIds,
            currentMatchIdx: 0, // 新名單，重置閱讀進度
          }, {merge: true});
        });

        // 等待這一批次全部完成
        await Promise.all(chunkPromises);
      }

      console.log("每日配對更新全數完成！");
    } catch (e: unknown) {
      console.error("每日配對更新發生嚴重錯誤:", e);
    }
  }
);
