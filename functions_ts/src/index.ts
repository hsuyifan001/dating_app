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
    schedule: "0 5,11,16,20 * * *", // 每天 5:00, 11:00, 16:00, 20:00 觸發 (UTC 時間)
    timeZone: "Asia/Taipei", // 設定時區為台灣
  },
  async (_event) => {
    const db = admin.firestore();
    const now = new Date();
    const todayKey = now.toISOString()
      .slice(0, 10)
      .replace(/-/g, ""); // YYYYMMDD

    try {
      // 取得所有用戶
      const usersSnapshot = await db.collection("users").get();
      const userPromises = usersSnapshot.docs.map(async (userDoc) => {
        const userId = userDoc.id;
        const userData = userDoc.data();
        let leftMatches = 25;
        const dailyMatchIds = new Set<string>();
        let existingUsers: admin.firestore.DocumentSnapshot[] = []; // 已儲存的用戶

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

          // 取得已儲存的用戶文檔
          if (userIds.length > 0) {
            existingUsers = await Promise.all(
              userIds.map((id: string) => db.collection("users").doc(id).get())
            );
          }
        }

        if (leftMatches <= 0) {
          // 如果已滿 25 人，直接使用已儲存的用戶
          const recommendedUsers = existingUsers;
          const recommendedUserIds = recommendedUsers.map((doc) => doc.id);

          // 更新快取（如果需要）
          await matchDocRef.set({
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            userIds: recommendedUserIds,
            currentMatchIdx: 0,
          });

          console.log(JSON.stringify({
            event: "dailyMatchUpdate",
            userId: userId,
            recommendedCount: recommendedUserIds.length,
            timestamp: new Date().toISOString(),
          }));
          return;
        }

        // 1. 取得已推播過的 userId
        const pushedSnapshot = await db.collection("users")
          .doc(userId)
          .collection("pushed")
          .get();
        const pushedIds = new Set(pushedSnapshot.docs.map((doc) => doc.id));

        // 2. 取得自己的配對條件與 likedTagCount 及 likedHabitCount
        const currentUserDepartment = userData.department || "";
        const matchSameDepartment = userData.matchSameDepartment || false;
        const matchGender = userData.matchGender || [];
        const matchSchools = userData.matchSchools || [];
        const likedTagCount = userData.likedTagCount || {};
        const likedHabitCount = userData.likedHabitCount || {};

        // 計算 top 3 tag 及 top 3 habit
        const sortedTags = Object.keys(likedTagCount).sort((a, b) =>
          likedTagCount[b] - likedTagCount[a]
        );
        const topTags = sortedTags.slice(0, 3);
        const sortedHabits = Object.keys(likedHabitCount).sort((a, b) =>
          likedHabitCount[b] - likedHabitCount[a]
        );
        const topHabits = sortedHabits.slice(0, 3);

        // 3. 對你按過愛心的人
        const likedMeSnapshot = await db.collection("likes")
          .where("to", "==", userId)
          .get();
        const likedMeIds = new Set(likedMeSnapshot.docs.map((doc) =>
          doc.data().from
        ));
        let likedMeUsers: admin.firestore.DocumentSnapshot[] = [];
        if (likedMeIds.size > 0) {
          const likedMeDocs = await Promise.all(
            Array.from(likedMeIds).map((id) =>
              db.collection("users").doc(id).get()
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

        // 4. 查詢一次所有候選人（符合性別、學校、系所且未被推播）
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
            const isSameDepartment = data?.department === currentUserDepartment;
            const isDailyMatched = dailyMatchIds.has(doc.id);

            if (matchSameDepartment === false && isSameDepartment) return false;
            return !isSelf && !isPushed && !isDailyMatched;
          });
        }

        // 5. 從中挑出 tag 及 habit 傾向者
        const filteredUsers = allCandidateDocs
          .filter((doc) => {
            const tags = doc.data()?.tags || [];
            const habits = doc.data()?.habits || [];
            const hasMatchingTag = tags.some((tag: string) =>
              topTags.includes(tag));
            const hasMatchingHabit = habits.some((habit: string) =>
              topHabits.includes(habit));
            return !likedMeUsers.some((d) => d.id === doc.id) &&
              (hasMatchingTag || hasMatchingHabit);
          })
          .slice(0, Math.min(15, leftMatches));
        leftMatches = Math.max(0, leftMatches - filteredUsers.length);

        // 6. 從剩下的中隨機選擇
        const remainingCandidates = allCandidateDocs.filter((doc) =>
          !likedMeUsers.some((d) => d.id === doc.id) &&
          !filteredUsers.some((d) => d.id === doc.id)
        );
        remainingCandidates.sort(() => Math.random() - 0.5); // 隨機排序
        const randomSelection = remainingCandidates.slice(0, leftMatches);
        leftMatches = Math.max(0, leftMatches - randomSelection.length);

        // 把不符合的人也加入（如果還有剩餘）
        let excludedUsers: admin.firestore.DocumentSnapshot[] = [];
        if (leftMatches > 0) {
          const allUsersSnapshot = await db.collection("users").get();
          excludedUsers = allUsersSnapshot.docs.filter((doc) => {
            const isSelf = doc.id === userId;
            const isPushed = pushedIds.has(doc.id);
            const isDailyMatched = dailyMatchIds.has(doc.id);
            const isInPreviousLists = (
              likedMeUsers.some((d) => d.id === doc.id) ||
              filteredUsers.some((d) => d.id === doc.id) ||
              randomSelection.some((d) => d.id === doc.id)
            );
            return !isSelf &&
              !isPushed &&
              !isDailyMatched &&
              !isInPreviousLists;
          }).slice(0, leftMatches);
        }

        // 7. 合併推薦名單（將已儲存的用戶放到最前面）
        const recommendedUsers = [
          ...existingUsers, // 已儲存的用戶放最前面
          ...likedMeUsers,
          ...filteredUsers,
          ...randomSelection,
          ...excludedUsers,
        ].slice(0, 25); // 確保總數不超過 25
        const recommendedUserIds = recommendedUsers.map((doc) => doc.id);

        // 8. 快取每日推薦
        await matchDocRef.set({
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          userIds: recommendedUserIds,
          currentMatchIdx: 0,
        });

        console.log(JSON.stringify({
          event: "dailyMatchUpdate",
          userId: userId,
          recommendedCount: recommendedUserIds.length,
          timestamp: new Date().toISOString(),
        }));
      });

      await Promise.all(userPromises);
      console.log("Daily match update completed for all users");
    } catch (e: unknown) {
      console.error("每日配對更新失敗:", e);
    }
  }
);
