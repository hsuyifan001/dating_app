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
    schedule: "0 5 * * *", // 每天 5:00 觸發
    timeZone: "Asia/Taipei", // 設定時區為台灣,
    memory: "1GiB",
    timeoutSeconds: 540,
  },
  async (_event) => {
    const db = admin.firestore();
    const now = new Date();
    const formatter = new Intl.DateTimeFormat("en-CA", {
      timeZone: "Asia/Taipei",
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    });
    const taipeiDateStr = formatter.format(now); // YYYY-MM-DD
    const todayKey = taipeiDateStr.replace(/-/g, ""); // YYYYMMDD

    try {
      // 1. 取得所有用戶 (這裡雖然是一次取得，但因為有 1GiB 記憶體通常撐得住)
      console.log("開始讀取所有用戶資料...");
      const usersSnapshot = await db.collection("users").get();
      const allUserDocs = usersSnapshot.docs;
      console.log(`共需處理 ${allUserDocs.length} 位用戶`);

      // =====================================================
      // 修改重點：設定分批大小 (Chunk Size)
      // 建議設定 20~50，避免同時發出太多連線導致 Timeout
      // =====================================================
      const CHUNK_SIZE = 50;

      // 將使用者切分成小批次
      const chunks = [];
      for (let i = 0; i < allUserDocs.length; i += CHUNK_SIZE) {
        chunks.push(allUserDocs.slice(i, i + CHUNK_SIZE));
      }

      // =====================================================
      // 修改重點：使用 for...of 迴圈「依序」處理每一批
      // =====================================================
      for (const [chunkIndex, chunk] of chunks.entries()) {
        console.log(
          `正在處理第 ${chunkIndex + 1} / ${chunks.length} 批 ` +
          `(本批 ${chunk.length} 人)...`
        );

        // 在這一批次內，我們可以使用 Promise.all 讓這 50 人並行處理
        // 這樣既有效率，又不會塞爆網路
        const chunkPromises = chunk.map(async (userDoc) => {
          const userId = userDoc.id;
          const userData = userDoc.data();
          let leftMatches = 25;
          const dailyMatchIds = new Set<string>();
          let existingUsers: admin.firestore.DocumentSnapshot[] = [];

          // --- 以下邏輯保持不變 ---

          // 0. 取得已儲存的配對快取
          const matchDocRef = db.collection("users")
            .doc(userId)
            .collection("dailyMatches")
            .doc(todayKey);

          const matchDoc = await matchDocRef.get();

          if (matchDoc.exists) {
            const data = matchDoc.data() || {};
            const userIds = data.userIds || [];
            leftMatches = 25 - userIds.length;
            dailyMatchIds.clear();
            userIds.forEach((id: string) => dailyMatchIds.add(id));

            if (userIds.length > 0) {
              // 注意：這裡如果 userIds 很多，也建議用 Promise.all 但數量不多通常沒事
              existingUsers = await Promise.all(
                userIds.map(
                  (id: string) => db.collection("users").doc(id).get()
                )
              );
            }
          }

          if (leftMatches <= 0) {
            // 已滿直接返回，不需運算
            // 若需要更新快取邏輯可保留，否則直接 return 節省資源
            const recommendedUsers = existingUsers;
            const recommendedUserIds = recommendedUsers.map((doc) => doc.id);

            // 確保即使沒運算也要寫入/更新時間戳記 (視需求而定)
            // 這裡保留你的原始邏輯
            await matchDocRef.set({
              createdAt: admin.firestore.FieldValue.serverTimestamp(),
              userIds: recommendedUserIds,
              currentMatchIdx: 0,
            });
            return;
          }

          // 1. 取得已推播過的 userId
          const pushedSnapshot = await db.collection("users")
            .doc(userId)
            .collection("pushed")
            .get();
          const pushedIds = new Set(pushedSnapshot.docs.map((doc) => doc.id));

          // 2. 取得條件
          const currentUserSchool = userData.school || "";
          const currentUserGender = userData.gender;
          const currentUserDepartment = userData.department || "";
          const matchSameDepartment = userData.matchSameDepartment || false;
          const matchGender = userData.matchGender || [];
          const matchSchools = userData.matchSchools || [];
          const likedTagCount = userData.likedTagCount || {};
          const likedHabitCount = userData.likedHabitCount || {};

          // 計算 top 3
          const sortedTags = Object.keys(likedTagCount).sort(
            (a, b) => likedTagCount[b] - likedTagCount[a]
          );
          const topTags = sortedTags.slice(0, 3);
          const sortedHabits = Object.keys(likedHabitCount).sort(
            (a, b) => likedHabitCount[b] - likedHabitCount[a]
          );
          const topHabits = sortedHabits.slice(0, 3);

          // 3. 對你按過愛心的人
          const likedMeSnapshot = await db.collection("likes")
            .where("to", "==", userId)
            .get();

          const likedMeIds = new Set(
            likedMeSnapshot.docs.map((doc) => doc.data().from)
          );
          let likedMeUsers: admin.firestore.DocumentSnapshot[] = [];

          if (likedMeIds.size > 0) {
            const likedMeDocs = await Promise.all(
              Array.from(likedMeIds).map(
                (id) => db.collection("users").doc(id).get()
              )
            );
            likedMeUsers = likedMeDocs.filter((doc) =>
              matchGender.includes(doc.data()?.gender) &&
              !pushedIds.has(doc.id) &&
              doc.id !== userId &&
              !dailyMatchIds.has(doc.id)
            ).slice(0, Math.min(5, leftMatches));
            leftMatches = Math.max(0, leftMatches - likedMeUsers.length);
          }

          // 4. 查詢候選人
          // ⚠️ 效能注意：這裡是在迴圈內做 Query，未來用戶多時會變慢，但目前先解 Timeout 問題
          let allCandidateDocs: admin.firestore.DocumentSnapshot[] = [];
          if (matchGender.length > 0 && matchSchools.length > 0) {
            const allCandidateSnapshot = await db.collection("users")
              .where("gender", "in", matchGender)
              .where("school", "in", matchSchools)
              .get();

            allCandidateDocs = allCandidateSnapshot.docs.filter((doc) => {
              const data = doc.data();
              const isSelf = doc.id === userId;
              const isPushed = pushedIds.has(doc.id);
              const isSameDepartment =
                data?.department === currentUserDepartment;
              const isDailyMatched = dailyMatchIds.has(doc.id);
              const isSameSchool = data?.school === currentUserSchool;

              if (matchSameDepartment === false &&
                  isSameSchool && isSameDepartment) {
                return false;
              }

              // 雙向配對檢查
              const candidateMatchGender = data?.matchGender || [];
              if (!candidateMatchGender.includes(currentUserGender)) {
                return false;
              }

              const candidateMatchSchools = data?.matchSchools || [];
              if (!candidateMatchSchools.includes(currentUserSchool)) {
                return false;
              }

              const candidateMatchSameDepartment =
                data?.matchSameDepartment || false;
              if (candidateMatchSameDepartment === false &&
                  isSameSchool && isSameDepartment) {
                return false;
              }

              return !isSelf && !isPushed && !isDailyMatched;
            });
          }

          // 5. 篩選 Tag/Habit
          const filteredUsers = allCandidateDocs
            .filter((doc) => {
              const tags = doc.data()?.tags || [];
              const habits = doc.data()?.habits || [];
              const hasMatchingTag = tags.some(
                (tag: string) => topTags.includes(tag)
              );
              const hasMatchingHabit = habits.some(
                (habit: string) => topHabits.includes(habit)
              );
              return (
                !likedMeUsers.some((d) => d.id === doc.id) &&
                (hasMatchingTag || hasMatchingHabit)
              );
            })
            .slice(0, Math.min(15, leftMatches));
          leftMatches = Math.max(0, leftMatches - filteredUsers.length);

          // 6. 隨機選擇
          const remainingCandidates = allCandidateDocs.filter((doc) =>
            !likedMeUsers.some((d) => d.id === doc.id) &&
            !filteredUsers.some((d) => d.id === doc.id)
          );
          remainingCandidates.sort(() => Math.random() - 0.5);
          const randomSelection = remainingCandidates.slice(0, leftMatches);

          // 7. 合併名單
          const recommendedUsers = [
            ...existingUsers,
            ...likedMeUsers,
            ...filteredUsers,
            ...randomSelection,
          ].slice(0, 25);

          const recommendedUserIds = recommendedUsers.map((doc) => doc.id);

          // 8. 寫入結果
          await matchDocRef.set({
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            userIds: recommendedUserIds,
            currentMatchIdx: 0,
          });

          // 簡化 Log，避免 Log 太多也被截斷
          // console.log(`User ${userId} updated.`);
        });

        // 等待這一批次 (50人) 全部做完
        await Promise.all(chunkPromises);

        // (選填) 如果資料庫寫入量非常大，可以在這裡加一個小延遲讓 Firestore 喘口氣
        // await new Promise(resolve => setTimeout(resolve, 100));
      }

      console.log("Daily match update completed for all users");
    } catch (e: unknown) {
      console.error("每日配對更新失敗:", e);
    }
  }
);
