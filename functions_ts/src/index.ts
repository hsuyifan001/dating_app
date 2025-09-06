// import {onCall, HttpsError} from "firebase-functions/v2/https";
// import * as admin from "firebase-admin";
// admin.initializeApp();

// export const sendNotification = onCall(async (request) => {
//   if (!request.auth) {
//     throw new HttpsError("unauthenticated", "必須登入才能發送通知");
//   }
//   const fcmToken = request.data.fcmToken;
//   const title = request.data.title;
//   const body = request.data.body;
//   const notificationData = request.data.data || {};

//   if (!fcmToken || !title || !body) {
//     throw new HttpsError("invalid-argument", "缺少必要參數：fcmToken、title、body");
//   }

//   const message: admin.messaging.Message = {
//     token: fcmToken,
//     notification: {title, body},
//     data: notificationData,
//     android: {priority: "high"},
//     apns: {payload: {aps: {badge: 1, sound: "default"}}},
//   };

//   try {
//     await admin.messaging().send(message);
//     return {success: true, message: "通知發送成功"};
//   } catch (e: unknown) {
//     console.error("發送通知失敗:", e);
//     throw new HttpsError("internal", `發送通知失敗: ${e}`);
//   }
// });
