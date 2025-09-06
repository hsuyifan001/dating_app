import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; // for DateFormat
import 'dart:async';
import 'dart:math';
// import 'package:cloud_functions/cloud_functions.dart';
import 'package:dating_app/utils/notification_util.dart';

class MatchPage extends StatefulWidget {
  const MatchPage({super.key});

  @override
  State<MatchPage> createState() => _MatchPageState();
}

class _MatchPageState extends State<MatchPage> {
  final user = FirebaseAuth.instance.currentUser;
  List<DocumentSnapshot> users = [];
  bool isLoading = true;
  bool isProcessing = false; // 防止連續點擊的變數
  // bool reachDailyLimit = false;
  int currentMatchIdx = 0;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<List<DocumentSnapshot>> _batchedUserDocsByIds(List<String> ids) async {
    const int batchSize = 10;
    List<DocumentSnapshot> allDocs = [];

    for (var i = 0; i < ids.length; i += batchSize) {
      final batch = ids.sublist(i, i + batchSize > ids.length ? ids.length : i + batchSize);
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: batch)
          .get();
      allDocs.addAll(snapshot.docs);
    }

    // 按原本 ids 順序排序
    allDocs.sort((a, b) => ids.indexOf(a.id).compareTo(ids.indexOf(b.id)));

    return allDocs;
  }

  Future<void> _loadUsers() async {
    if (user == null) return;
    final currentUserId = user!.uid;
    final now = DateTime.now();
    final todayKey = DateFormat('yyyyMMdd').format(now);
    int leftMatches = 25;

    final matchDocRef = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .collection('dailyMatches')
        .doc(todayKey);

    Set<String> dailyMatchIds = {};

    // 0. 取得已儲存的配對快取
    try {
      print('[Step 0] 取得當日配對快取');
      final matchDoc = await matchDocRef.get();

      if (matchDoc.exists) {
        print('[Step 0] 快取存在，讀取資料');
        final data = matchDoc.data() ?? {};
        final userIds = List<String>.from(data['userIds'] ?? []);
        final matchUserCount = userIds.length;
        leftMatches = 25 - matchUserCount;
        // reachDailyLimit = data['ReachDailyLimit'] == true;
        currentMatchIdx = data['currentMatchIdx'] ?? 0;
        dailyMatchIds = userIds.toSet();
        print('[Step 0] currentMatchIdx : ${currentMatchIdx}');

        // 先把快取的用戶取出
        final userDocs = await _batchedUserDocsByIds(userIds);
        users = userDocs;

        if (users.length >= 25) {
          setState(() {
            isLoading = false;
          });
          print('[Step 0] 快取人數已滿 25，結束');
          return;
        }

        // if (reachDailyLimit) {
        //   setState(() {
        //     users = [];
        //     isLoading = false;
        //   });
        //   if (context.mounted) {
        //     ScaffoldMessenger.of(context).showSnackBar(
        //       const SnackBar(content: Text('今日配對上限已到，請明天再來！')),
        //     );
        //   }
        //   print('[Step 0] 今日配對已達上限，結束');
        //   return;
        // }

        // 人數不足，繼續補人
        print('[Step 0] 快取人數不足 (${users.length}/25)，開始補人流程...');
      }
    } catch (e, st) {
      print('[Error Step 0] 讀取當日配對快取失敗: $e');
      print(st);
    }

    print('leftMatches: $leftMatches');

    // 1. 取得已推播過的 userId
    Set<String> pushedIds = {};
    try {
      print('[Step 1] 取得已推播過的 userId');
      final pushedSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .collection('pushed')
          .get();
      pushedIds = pushedSnapshot.docs.map((doc) => doc.id).toSet();
      print('[Step 1] 已推播 userId 數量: ${pushedIds.length}');
    } catch (e, st) {
      print('[Error Step 1] 取得已推播 userId 失敗: $e');
      print(st);
    }

    // 2. 取得自己的配對條件與 likedTagCount 及 likedHabitCount
    String currentUserDepartment = '';
    bool matchSameDepartment = false;
    List<String> matchGender = [];
    List<String> matchSchools = [];
    Map<String, int> likedTagCount = {};
    Map<String, int> likedHabitCount = {};
    try {
      print('[Step 2] 取得使用者資料與配對條件');
      final currentUserDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .get();
      final currentUserData = currentUserDoc.data() ?? {};
      currentUserDepartment = currentUserData['department'] ?? '';
      matchSameDepartment = currentUserData['matchSameDepartment'] ?? false;
      matchGender = List<String>.from(currentUserData['matchGender'] ?? []);
      matchSchools = List<String>.from(currentUserData['matchSchools'] ?? []);
      likedTagCount = Map<String, int>.from(currentUserData['likedTagCount'] ?? {});
      likedHabitCount = Map<String, int>.from(currentUserData['likedHabitCount'] ?? {});
      print('[Step 2] 使用者配對條件：性別(${matchGender.length})、學校(${matchSchools.length})、同系所匹配: $matchSameDepartment');
    } catch (e, st) {
      print('[Error Step 2] 取得使用者資料失敗: $e');
      print(st);
    }

    // 計算 top 3 tag 及 top 3 habit
    final sortedTags = likedTagCount.keys.toList()
      ..sort((a, b) => likedTagCount[b]!.compareTo(likedTagCount[a]!));
    final topTags = sortedTags.take(3).toList();
    final sortedHabits = likedHabitCount.keys.toList()
      ..sort((a, b) => likedHabitCount[b]!.compareTo(likedHabitCount[a]!));
    final topHabits = sortedHabits.take(3).toList();
    print('[Info] Top tags: $topTags');
    print('[Info] Top habits: $topHabits');

    // 3. 對你按過愛心的人
    Set<String> likedMeIds = {};
    List<DocumentSnapshot> likedMeUsers = [];
    try {
      print('[Step 3] 取得按過愛心的使用者');
      final likedMeSnapshot = await FirebaseFirestore.instance
          .collection('likes')
          .where('to', isEqualTo: currentUserId)
          .get();
      likedMeIds = likedMeSnapshot.docs.map((doc) => doc['from'] as String).toSet();
      print('[Step 3] 按愛心使用者數量: ${likedMeIds.length}');

      if (likedMeIds.isNotEmpty) {
        print('[Step 3] 取得按愛心使用者資料');
        final allDocs = await _batchedUserDocsByIds(likedMeIds.toList());
        print('[Step 3] 取得資料數量: ${allDocs.length}');

        likedMeUsers = allDocs.where((doc) =>
            matchGender.contains(doc['gender']) &&
            !pushedIds.contains(doc.id) &&
            doc.id != currentUserId &&
            !dailyMatchIds.contains(doc.id)
        ).toList();

        print('[Step 3] 過濾後按愛心使用者數量: ${likedMeUsers.length}');

        likedMeUsers = likedMeUsers.take(min(5, leftMatches)).toList();
        leftMatches = leftMatches <= likedMeUsers.length ? 0 : leftMatches - likedMeUsers.length;

        for (var doc in likedMeUsers) {
          print('[Step 3] LikedMeUserId: ${doc.id}');
        }
      }
    } catch (e, st) {
      print('[Error Step 3] 取得按愛心使用者資料失敗: $e');
      print(st);
    }

    print('leftMatches: $leftMatches');

    // 4. 查詢一次所有候選人（符合性別、學校、系所且未被推播）
    List<DocumentSnapshot> allCandidateDocs = [];
    try {
      print('[Step 4] 取得所有候選人');
      if (matchGender.isEmpty || matchSchools.isEmpty) {
        print('[Step 4] matchGender 或 matchSchools 為空，跳過查詢');
      } else {
        final allCandidateSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .where('gender', whereIn: matchGender)
            .where('school', whereIn: matchSchools)
            .get();
        allCandidateDocs = allCandidateSnapshot.docs.where((doc) {
          final isSelf = doc.id == currentUserId;
          final isPushed = pushedIds.contains(doc.id);
          final isSameDepartment = doc['department'] == currentUserDepartment;
          final isDailyMatched = dailyMatchIds.contains(doc.id);

          if (matchSameDepartment == false && isSameDepartment) {
            return false; // 排除同系所
          }

          return !isSelf && !isPushed && !isDailyMatched;
        }).toList();
        print('[Step 4] 符合條件的候選人數量: ${allCandidateDocs.length}');
        for (var doc in allCandidateDocs) {
          print('[Step 4] CandidateUser: ${doc.id}');
        }
      }
    } catch (e, st) {
      print('[Error Step 4] 取得候選人資料失敗: $e');
      print(st);
    }

    // 5. 從中挑出 tag 及 habit 傾向者
    List<DocumentSnapshot> filteredUsers = [];
    // Set<String> filteredUserIds = {};
    try {
      print('[Step 5] 挑出 tag 及 habit 傾向者');
      filteredUsers = allCandidateDocs
          .where((doc) =>
              !likedMeUsers.map((d) => d.id).contains(doc.id) &&
              !users.map((d) => d.id).contains(doc.id) &&
              ((doc['tags'] as List).any((tag) => topTags.contains(tag)) ||
              (doc['habits'] as List).any((habit) => topHabits.contains(habit))))
          .take(min(15, leftMatches))
          .toList();
      leftMatches = leftMatches <= filteredUsers.length ? 0 : leftMatches - filteredUsers.length;

      // filteredUserIds = filteredUsers.map((doc) => doc.id).toSet();
      print('[Step 5] 過濾後候選人數量: ${filteredUsers.length}');

      for (var doc in filteredUsers) {
        print('[Step 5] FilteredUser: ${doc.id} - ${doc['name']}');
      }
    } catch (e, st) {
      print('[Error Step 5] 過濾 tag/habit 使用者失敗: $e');
      print(st);
    }

    print('leftMatches: $leftMatches');

    // 6. 從剩下的中隨機選擇
    List<DocumentSnapshot> randomUsers = [];
    List<DocumentSnapshot> randomSelection = [];
    try {
      print('[Step 6] 從剩餘候選人隨機選擇');
      randomUsers = allCandidateDocs
          .where((doc) =>
              !users.map((d) => d.id).contains(doc.id) &&
              !likedMeUsers.map((d) => d.id).contains(doc.id) &&
              !filteredUsers.map((d) => d.id).contains(doc.id))
          .toList()
        ..shuffle();
      randomSelection = randomUsers.take(leftMatches).toList();
      print('[Step 6] 隨機選擇人數: ${randomSelection.length}');
      leftMatches -= randomSelection.length;

      for (var doc in randomSelection) {
        print('[Step 6] RandomSelection: ${doc.id} - ${doc['name']}');
      }
    } catch (e, st) {
      print('[Error Step 6] 隨機選擇使用者失敗: $e');
      print(st);
    }

    print('leftMatches: $leftMatches');

    // 把不符合的人也加入
    List<DocumentSnapshot> excludedUsers = [];
    if (leftMatches > 0) {
      try {
        print('[Step 6] 把不符合的人也加入');
        // 限制查詢數量，提高效率
        final allUsersSnapshot = await FirebaseFirestore.instance
            .collection('users')
            .get();

        excludedUsers = allUsersSnapshot.docs.where((doc) {
          final isSelf = doc.id == currentUserId;
          final isPushed = pushedIds.contains(doc.id);
          final isDailyMatched = dailyMatchIds.contains(doc.id);
          final isInPreviousLists = users.map((d) => d.id).contains(doc.id) ||
              likedMeUsers.map((d) => d.id).contains(doc.id) ||
              filteredUsers.map((d) => d.id).contains(doc.id) ||
              randomUsers.map((d) => d.id).contains(doc.id);

          return !isSelf && !isPushed && !isDailyMatched && !isInPreviousLists;
        }).toList();

        leftMatches -= excludedUsers.length;

        print('[Step 6] 被排除的人數: ${excludedUsers.length}');
        for (var doc in excludedUsers) {
          final name = doc['name'] ?? '未知用戶';
          print('[Step 6] ExcludedUser: ${doc.id} - $name');
        }

        if (excludedUsers.isEmpty && leftMatches > 0) {
          print('[Step 6] 無符合條件的排除用戶，考慮放寬條件或通知用戶');
          // 可選：顯示提示
          // if (context.mounted) {
          //   ScaffoldMessenger.of(context).showSnackBar(
          //     const SnackBar(content: Text('無更多用戶可推薦，請明天再試！')),
          //   );
          // }
        }
      } catch (e, st) {
        print('[Error Step 6] 把不符合的人也加入失敗: $e');
        print(st);
        if (context.mounted) {
          // ScaffoldMessenger.of(context).showSnackBar(
          //   const SnackBar(content: Text('載入推薦用戶失敗，請稍後再試')),
          // );
        }
      }
    }

    // 7. 合併推薦名單
    final recommendedUsers = [...users, ...likedMeUsers, ...filteredUsers, ...randomSelection, ...excludedUsers];
    print('[Step 7] 合併推薦名單數量: ${recommendedUsers.length}');

    setState(() {
      users = recommendedUsers;
      isLoading = false;
    });

    // 8. 記錄 pushed
    // try {
    //   print('[Step 8] 記錄 pushed');
    //   for (var doc in recommendedUsers) {
    //     await FirebaseFirestore.instance
    //         .collection('users')
    //         .doc(currentUserId)
    //         .collection('pushed')
    //         .doc(doc.id)
    //         .set({'pushedAt': FieldValue.serverTimestamp()});
    //     print('[Step 8] 記錄 userId ${doc.id}');
    //   }
    // } catch (e, st) {
    //   print('[Error Step 8] 記錄 pushed 失敗: $e');
    //   print(st);
    // }

    // 9. 快取每日推薦
    try {
      print('[Step 9] 快取每日推薦');
      await matchDocRef.set({
        'createdAt': FieldValue.serverTimestamp(),
        'userIds': recommendedUsers.map((doc) => doc.id).toList(),
        // 'ReachDailyLimit': false,
        'currentMatchIdx': currentMatchIdx,
      });
      print('[Step 9] 快取每日推薦完成');
    } catch (e, st) {
      print('[Error Step 9] 快取每日推薦失敗: $e');
      print(st);
    }
  }

  // ...existing code...

  Future<void> _showNextUser() async {
    final currentUserId = user!.uid;
    final todayKey = DateFormat('yyyyMMdd').format(DateTime.now());
    final matchDocRef = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .collection('dailyMatches')
        .doc(todayKey);

    final matchDoc = await matchDocRef.get();
    if (!matchDoc.exists) return;

    if(currentMatchIdx < users.length) {
      currentMatchIdx++;
      await matchDocRef.update({'currentMatchIdx': currentMatchIdx});
    }

    setState(() {});

  }
  
  Future<void> _handleLike(String targetUserId) async {
    if (isProcessing) return; // 如果正在處理，直接返回
    setState(() {
      isProcessing = true; // 設定為正在處理
    });
    
    final firestore = FirebaseFirestore.instance;
    final currentUserId = user!.uid;

    // 1. 儲存 like 記錄
    await firestore
        .collection('likes')
        .doc('$currentUserId\_$targetUserId')
        .set({
      'from': currentUserId,
      'to': targetUserId,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // 2. 儲存 pushed 紀錄
    await firestore
        .collection('users')
        .doc('$currentUserId')
        .collection('pushed')
        .doc(targetUserId)
        .set({
      'pushedAt': FieldValue.serverTimestamp(),
    });

    // 2. 取得被按愛心者的 tags 及 habits
    final targetUserDoc =
        await firestore.collection('users').doc(targetUserId).get();
    final targetTags = List<String>.from(targetUserDoc['tags'] ?? []);
    final targetHabits = List<String>.from(targetUserDoc['habits'] ?? []);

    // 3. 更新當前使用者的 likedTagCount 及 likedHabitCount 統計
    final currentUserRef = firestore.collection('users').doc(currentUserId);
    final currentUserDoc = await currentUserRef.get();
    final currentLikedTagCount =
        Map<String, dynamic>.from(currentUserDoc.data()?['likedTagCount'] ?? {});
    final currentLikedHabitCount =
        Map<String, dynamic>.from(currentUserDoc.data()?['likedHabitCount'] ?? {});

    for (final tag in targetTags) {
      currentLikedTagCount[tag] = (currentLikedTagCount[tag] ?? 0) + 1;
    }
    for (final habit in targetHabits) {
      currentLikedHabitCount[habit] = (currentLikedHabitCount[habit] ?? 0) + 1;
    }

    await currentUserRef.update({
      'likedTagCount': currentLikedTagCount,
      'likedHabitCount': currentLikedHabitCount,
    });

    // 4. 檢查是否互相按愛心（已存在對方的 like）
    final reverseLike = await firestore
        .collection('likes')
        .doc('$targetUserId\_$currentUserId')
        .get();

    // print('反向按讚存在：${reverseLike.exists}'); // debug用
    if (reverseLike.exists) {
      // 先顯示彈窗（不等寫入）
      if (context.mounted) {
        showMatchDialog(context);
      }

      // 背景處理聊天室與 matches 寫入
      unawaited(() async {
        // 建立聊天室（確保不存在才建立）
        await createChatRoom(currentUserId, targetUserId);

        // 建立 matches 紀錄
        final timestamp = FieldValue.serverTimestamp();
        await Future.wait([
          firestore.collection('users').doc(currentUserId).collection('matches').doc(targetUserId).set({
            'matchedUserId': targetUserId,
            'matchedAt': timestamp,
          }),
          firestore.collection('users').doc(targetUserId).collection('matches').doc(currentUserId).set({
            'matchedUserId': currentUserId,
            'matchedAt': timestamp,
          }),
        ]);
        
        // 發送推播通知
        await sendPushNotification(
          targetUserId: targetUserId,
          title: '配對成功！',
          body: '你和 ${currentUserDoc['name'] ?? '某人'} 配對成功了，快去聊聊吧 💕',
          data: {
            'type': 'match',
            'chatRoomId': _getMatchRoomId(currentUserId, targetUserId), // 假設聊天室 ID 格式
          },
        );
      }());

      // 彈窗關閉後才換下一個人
      _showNextUser();
      setState(() {
        isProcessing = false; // 處理完成，允許下一次點擊
      });
    } else {
      _showNextUser();
      setState(() {
        isProcessing = false; // 處理完成，允許下一次點擊
      });
    }
  }

  Future<void> _handleDislike(String targetUserId) async {
    // debug用
    // final currentUserId = user!.uid;
    // final allCandidateSnapshot = await FirebaseFirestore.instance
    //     .collection('users')
    //     .get();
    // final allCandidateDocs = allCandidateSnapshot.docs.where((doc) {
    //   final isSelf = doc.id == currentUserId;

    //   return !isSelf;
    // }).toList();

    // for(final candidate in allCandidateDocs) {
    //   if(!users.contains(candidate)) {
    //     users.add(candidate);
    //   }
    // }


    if (isProcessing) return; // 如果正在處理，直接返回
    setState(() {
      isProcessing = true; // 設定為正在處理
    });

    final firestore = FirebaseFirestore.instance;
    final currentUserId = user!.uid;

    // 儲存 pushed 紀錄
    await firestore
        .collection('users')
        .doc('$currentUserId')
        .collection('pushed')
        .doc(targetUserId)
        .set({
      'pushedAt': FieldValue.serverTimestamp(),
    });

    // 你可以在這裡實作記錄不喜歡的邏輯，例如加入一個 dislikes collection
    _showNextUser();
    setState(() {
        isProcessing = false; // 處理完成，允許下一次點擊
      });
  }

  // 顯示配對成功
  void showMatchDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false, // 點擊背景不會關閉
      barrierColor: Colors.black.withOpacity(0.5), // 半透明背景
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent, // 完全透明背景
          elevation: 0,
          insetPadding: EdgeInsets.all(20), // 控制距離螢幕邊緣的間距
          child: Stack(
            children: [
              // 圖片
              Image.asset(
                'assets/match_success.png',
                fit: BoxFit.contain,
              ),
              // 右上角關閉按鈕
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, size: 32, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Future<void> sendPushNotification({
  //   required String targetUserId,
  //   required String title,
  //   required String body,
  //   Map<String, String>? data,
  // }) async {
  //   try {
  //     // 1. 取得目標用戶的 FCM 權杖
  //     final firestore = FirebaseFirestore.instance;
  //     final targetUserDoc = await firestore.collection('users').doc(targetUserId).get();
  //     final fcmToken = targetUserDoc.data()?['fcmToken'] as String?;

  //     if (fcmToken == null || fcmToken.isEmpty) {
  //       print('目標用戶 ($targetUserId) 無有效的 FCM 權杖');
  //       return;
  //     }

  //     // 2. 呼叫 Cloud Functions 的 sendNotification
  //     final callable = FirebaseFunctions.instance.httpsCallable('sendNotification');
  //     await callable.call({
  //       'fcmToken': fcmToken,
  //       'title': title,
  //       'body': body,
  //       'data': data ?? {},
  //     });

  //     // 3. 在目標用戶的notices中存放通知
  //     await firestore.collection('users').doc(targetUserId).collection('notices').add({
  //       'title': title,
  //       'body': body,
  //       'data': data ?? {},
  //       'timestamp': FieldValue.serverTimestamp(),
  //       'isRead': false,
  //     });

  //     print('推播通知已發送給用戶 $targetUserId: $title - $body');
  //   } catch (e) {
  //     print('發送推播通知失敗: $e');
  //   }
  // }

  Future<void> createChatRoom(String userA, String userB) async {
    final chatId = _getMatchRoomId(userA, userB); // 兩個 uid 排序後組成唯一 id

    final chatDoc = FirebaseFirestore.instance.collection('chats').doc(chatId);

    // 如果聊天室不存在，才建立
    if (!(await chatDoc.get()).exists) {
      final userADoc = await FirebaseFirestore.instance.collection('users').doc(userA).get();
      final userBDoc = await FirebaseFirestore.instance.collection('users').doc(userB).get();

      final userAName = userADoc.data()?['name'] ?? 'User A';
      final userBName = userBDoc.data()?['name'] ?? 'User B';

      await chatDoc.set({
        'members': [userA, userB],
        'type': 'match',
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': '配對成功',
        'lastMessageTime': FieldValue.serverTimestamp(),
        'groupName': '',

        // 對每個成員儲存對方的名字
        'displayNames': {
          userA: userBName,
          userB: userAName,
        },
        'displayPhotos': {
          userA: userADoc.data()?['photoUrl'] ?? '',
          userB: userBDoc.data()?['photoUrl'] ?? '',
        }
      });
    }
  }

  // 讓 chatId 在兩人之間唯一
  String _getMatchRoomId(String id1, String id2) {
    final ids = [id1, id2]..sort();
    return ids.join('_');
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    // debug用
    // int cnt = 1;
    // for(final user in users) {
    //   print('第${cnt++}位使用者：${user.data()}');
    // };
    // print('已輸出所有配對者');

    // 達到配對上限時顯示的頁面
    if(currentMatchIdx == users.length) {
      final screenWidth = MediaQuery.of(context).size.width;
      final screenHeight = MediaQuery.of(context).size.height;

      return Center(
        child: Image.asset(
          'assets/match_limit.png',
          width: screenWidth * (0.9), // 依需求調整大小
          height: screenHeight * (0.9),
        ),
      );
    }

    // Figma 畫布尺寸
    const figmaWidth = 412.0;
    const figmaHeight = 917.0;
  
    // 名字方框在 figma 的位置與大小
    const nameBoxLeft = 45.0;
    const nameBoxTop = 480.0;
    const nameBoxWidth = 180.0; // 原本是 128.0
    const nameBoxHeight = 54.0;
  
    const tagBoxLeft = 45.0;
    const tagBoxTop = 560.0;
    const tagBoxWidth = 104.0; // 原本是 104.0
    const tagBoxHeight = 39.0; // 原本是 39.0
    const tagBoxHSpace = 8.0; // 水平間距
    const tagBoxVSpace = 9.0; // 垂直間距
    return Container(
      color: const Color(0xFFE8FFFB), // 設定整個背景色
      child: LayoutBuilder(
        builder: (context, constraints) {
          final screenWidth = constraints.maxWidth;
          final screenHeight = constraints.maxHeight;
          // 算出背景圖在螢幕上的實際顯示區域
          final bgAspect = figmaWidth / figmaHeight;
          final screenAspect = screenWidth / screenHeight;

          double bgWidth, bgHeight, bgLeft, bgTop;
          if (screenAspect > bgAspect) {
            // 螢幕比較寬，背景圖高度填滿，左右有留白
            bgHeight = screenHeight;
            bgWidth = bgHeight * bgAspect;
            bgLeft = (screenWidth - bgWidth) / 2;
            bgTop = 0;
          } else {
            // 螢幕比較窄，背景圖寬度填滿，上下有留白
            bgWidth = screenWidth;
            bgHeight = bgWidth / bgAspect;
            bgLeft = 0;
            bgTop = (screenHeight - bgHeight) / 2;
          }

          // 依照背景圖實際顯示區域計算元件位置
          final nameBoxLeftPx = bgLeft + bgWidth * (nameBoxLeft / figmaWidth);
          final nameBoxTopPx = bgTop + bgHeight * (nameBoxTop / figmaHeight);
          final nameBoxWidthPx = bgWidth * (nameBoxWidth / figmaWidth);
          final nameBoxHeightPx = bgHeight * (nameBoxHeight / figmaHeight);
          final tagBoxLeftPx = bgLeft + bgWidth * (tagBoxLeft / figmaWidth);
          final tagBoxTopPx = bgTop + bgHeight * (tagBoxTop / figmaHeight);
          final tagBoxWidthPx = bgWidth * (tagBoxWidth / figmaWidth);
          final tagBoxHeightPx = bgHeight * (tagBoxHeight / figmaHeight);
          final tagBoxHSpacePx = bgWidth * (tagBoxHSpace / figmaWidth);
          final tagBoxVSpacePx = bgHeight * (tagBoxVSpace / figmaHeight);
          
          // 取得標籤資料
          final tags = users.isNotEmpty
              ? ((users[currentMatchIdx].data() as Map)['tags'] as List<dynamic>? ?? [])
              : List.generate(6, (i) => '標籤${i + 1}');

          return Stack(
            children: [
              //使用者照片
              Positioned(
                left: bgLeft + bgWidth * (64.0 / figmaWidth),
                top: bgTop + bgHeight * (126.0 / figmaHeight),
                width: bgWidth * (287.0 / figmaWidth),
                height: bgWidth * (287.0 / figmaWidth), // 保持正方形
                child: GestureDetector(
                  onTap: users.isNotEmpty
                    ? () => _showUserDetail(  context,  Map<String, dynamic>.from(users[currentMatchIdx].data() as Map),)
                    : null,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: users.isNotEmpty && (users[currentMatchIdx].data() as Map)['photoUrl'] != null && (users[currentMatchIdx].data() as Map)['photoUrl'].toString().isNotEmpty
                        ? Image.network(
                            (users[currentMatchIdx].data() as Map)['photoUrl'],
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Image.asset(
                              'assets/match_default.jpg',
                              fit: BoxFit.cover,
                            ),
                          )
                        : Image.asset(
                            'assets/match_default.jpg',
                            fit: BoxFit.cover,
                          ),
                  ),
                ),
              ),
              
              // 背景圖片
              Positioned.fill(
                child: IgnorePointer(
                  child: Image.asset(
                    'assets/match_background.png',
                    fit: BoxFit.contain,
                    alignment: Alignment.topCenter,
                  ),
                ),
              ),
              
              
              // 名字方框
              Positioned(
                left: nameBoxLeftPx,
                top: nameBoxTopPx,
                width: nameBoxWidthPx,
                height: nameBoxHeightPx,
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.pink.shade200, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.pink.shade50,
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child:Text(
                      users.isNotEmpty
                          ? "  " + ((users[currentMatchIdx].data() as Map)['name'] ?? '名字') + "  "
                          : ' 名字 ',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ),
              ),

              // 標籤框框
              for (int i = 0; i < (tags.length > 6 ? 6 : tags.length); i++)
                Positioned(
                  left: tagBoxLeftPx + (i % 3) * (tagBoxWidthPx + tagBoxHSpacePx),
                  top: tagBoxTopPx + (i ~/ 3) * (tagBoxHeightPx + tagBoxVSpacePx),
                  width: tagBoxWidthPx,
                  height: tagBoxHeightPx,
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.pink.shade100, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.pink.shade50,
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child:Text(
                        "  "+tags[i].toString().replaceAll(RegExp(r'\r?\n') , '')+ "  ", // 去掉換行
                        style: const TextStyle(
                          color: Colors.pink,
                          fontWeight: FontWeight.w500,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      )
                      
                  ),
                ),

              //叉叉按鈕
              Positioned(
                left: bgLeft + bgWidth * (45.0 / figmaWidth),
                top: bgTop + bgHeight * (701.0 / figmaHeight),
                width: bgWidth * (124.0 / figmaWidth),
                height: bgWidth * (124.0 / figmaWidth), // 用寬度比例確保圓形
                child: GestureDetector(
                  onTap: users.isNotEmpty ? () => _handleDislike(users[currentMatchIdx].id) : null,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black26, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Image.asset(
                       'assets/no.png',
                       width: bgWidth * (124.0 / figmaWidth) * 0.7, // 70% 按鈕直徑
                       height: bgWidth * (124.0 / figmaWidth) * 0.7,
                       fit: BoxFit.contain,
                     ),
                    ),
                  ),
                ),
              ),
              
              // 愛心按鈕
              Positioned(
                left: bgLeft + bgWidth * (248.0 / figmaWidth),
                top: bgTop + bgHeight * (701.0 / figmaHeight),
                width: bgWidth * (124.0 / figmaWidth),
                height: bgWidth * (124.0 / figmaWidth), // 用寬度比例確保圓形
                child: GestureDetector(
                  onTap: users.isNotEmpty ? () => _handleLike(users[currentMatchIdx].id) : null,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.black26, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black12,
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Image.asset(
                        'assets/good.png',
                        width: bgWidth * (124.0 / figmaWidth) * 0.7, // 70% 按鈕直徑
                        height: bgWidth * (124.0 / figmaWidth) * 0.7,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
              // 其他元件也請用同樣方式計算位置
            ],
          );
        },
      ),
    );
  }


  // 顯示使用者詳細資料
  void _showUserDetail(BuildContext context, Map<String, dynamic> userData) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // 基準尺寸 (Figma 畫布)
    const baseWidth = 412.0;
    const baseHeight = 917.0;

    // 依據螢幕比例計算縮放
    double w(double value) => value * screenWidth / baseWidth;
    double h(double value) => value * screenHeight / baseHeight;

    final double tagWidth = w(85);
    final double tagSpacing = w(12);
    final double maxWrapWidth = tagWidth * 3 + tagSpacing * 2;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return FractionallySizedBox(
          heightFactor: 0.75, // 佔螢幕 75%
          child: Padding(
            padding: EdgeInsets.all(w(14)),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: h(10)),

                  // 頭像 + 姓名 + icon 疊加
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 頭像
                      Container(
                        width: w(102),
                        height: w(102),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: const Color.fromRGBO(255, 200, 202, 1),
                            width: 5,
                          ),
                        ),
                        child: CircleAvatar(
                          backgroundImage: (userData['photoUrl'] != null &&
                                  userData['photoUrl'].toString().isNotEmpty)
                              ? NetworkImage(userData['photoUrl'])
                              : const AssetImage('assets/match_default.jpg')
                                  as ImageProvider,
                          backgroundColor: Colors.transparent,
                        ),
                      ),

                      SizedBox(width: w(15)),

                      // 姓名
                      Expanded(
                        child: SizedBox(
                          height: w(102),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                userData['name'] ?? '未設定名稱',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: 'Kiwi Maru',
                                  fontWeight: FontWeight.w500,
                                  fontSize: 24,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                      // icon
                      SizedBox(
                        width: w(102),
                        height: w(102),
                        child: Transform.rotate(
                          angle: 14.53 * 3.1415926535 / 180,
                          child: Image.asset(
                            'assets/icon.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: h(40)),

                  Transform.translate(
                    offset: Offset(0, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildInfoLine("學校", userData['school']),
                        _buildInfoLine("科系", userData['department']),
                        _buildInfoLine("學歷", userData['educationLevels']),
                        _buildInfoLine("性別", userData['gender']),
                        _buildInfoLine("生日", userData['birthday']),
                        _buildInfoLine("身高", userData['height']),
                        _buildInfoLine("MBTI", userData['mbti']),
                        _buildInfoLine("星座", userData['zodiac']),
                        const SizedBox(height: 12),

                        // 自我介紹
                        Text(
                          '自我介紹：',
                          style: const TextStyle(
                            fontFamily: 'Kiwi Maru',
                            fontWeight: FontWeight.w500,
                            fontSize: 22,
                            color: Colors.black,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          userData['selfIntro'] ?? '尚未填寫',
                          style: const TextStyle(
                            fontSize: 18,
                            color: Colors.black87,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: h(20)),

                  // 個性標籤
                  if (userData['tags'] != null && userData['tags'] is List)
                    _buildTagBlock("個性標籤", userData['tags'], tagWidth, tagSpacing, maxWrapWidth, h),

                  SizedBox(height: h(20)),

                  // 習慣
                  if (userData['habits'] != null && userData['habits'] is List)
                    _buildTagBlock("興趣", userData['habits'], tagWidth, tagSpacing, maxWrapWidth, h),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 共用文字列 (key: value)
  Widget _buildInfoLine(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        '$label：${value ?? '尚未填寫'}',
        style: const TextStyle(
          fontFamily: 'Kiwi Maru',
          fontWeight: FontWeight.w500,
          fontSize: 20,
          color: Colors.black,
        ),
      ),
    );
  }

  /// 共用多選區塊 (Wrap)
  Widget _buildTagBlock(String title, List<dynamic> items, double tagWidth,
      double tagSpacing, double maxWrapWidth, double Function(double) h) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$title：',
          style: const TextStyle(
            fontFamily: 'Kiwi Maru',
            fontWeight: FontWeight.w600,
            fontSize: 22,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.topLeft,
          child: Container(
            width: maxWrapWidth,
            child: Wrap(
              spacing: tagSpacing,
              runSpacing: h(8),
              children: [
                for (int i = 0; i < items.length; i++)
                  Container(
                    width: tagWidth,
                    height: h(39),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.pink.shade100, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.pink.shade50,
                          blurRadius: 2,
                          offset: const Offset(0, 1),
                        ),
                      ],
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        "  ${items[i]}  ",
                        style: const TextStyle(
                          color: Colors.pink,
                          fontWeight: FontWeight.w500,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

}
