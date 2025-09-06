import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

Future<void> sendPushNotification({
  required String targetUserId,
  required String title,
  required String body,
  Map<String, String>? data,
}) async {
  try {
    final firestore = FirebaseFirestore.instance;
    final targetUserDoc = await firestore.collection('users').doc(targetUserId).get();
    final fcmToken = targetUserDoc.data()?['fcmToken'] as String?;

    if (fcmToken == null || fcmToken.isEmpty) {
      print('目標用戶 ($targetUserId) 無有效的 FCM 權杖');
      return;
    }

    final callable = FirebaseFunctions.instance.httpsCallable('sendNotification');
    await callable.call({
      'fcmToken': fcmToken,
      'title': title,
      'body': body,
      'data': data ?? {},
    });

    await firestore.collection('users').doc(targetUserId).collection('notices').add({
      'title': title,
      'body': body,
      'data': data ?? {},
      'timestamp': FieldValue.serverTimestamp(),
      'isRead': false,
    });

    print('推播通知已發送給用戶 $targetUserId: $title - $body');
  } catch (e) {
    print('發送推播通知失敗: $e');
  }
}