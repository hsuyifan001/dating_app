import 'package:cloud_firestore/cloud_firestore.dart';

class FcmService {
  static String? pendingFcmToken;

  static void setPendingToken(String? token) {
    pendingFcmToken = token;
  }

  // 如果 users/{userId} 已存在，寫入 pending token（並可選擇清除 pending）
  static Future<void> saveTokenIfUserProfileExists(String userId) async {
    if (pendingFcmToken == null) return;
    final docRef = FirebaseFirestore.instance.collection('users').doc(userId);
    final doc = await docRef.get();
    if (doc.exists) {
      await docRef.set({'fcmToken': pendingFcmToken}, SetOptions(merge: true));
      // 若要寫入後清除 pending，解除下行註解：
      // pendingFcmToken = null;
    }
  }
}