import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; // for DateFormat
import 'dart:async';
import 'dart:math';

class MatchPage extends StatefulWidget {
  const MatchPage({super.key});

  @override
  State<MatchPage> createState() => _MatchPageState();
}

class _MatchPageState extends State<MatchPage> {
  final user = FirebaseAuth.instance.currentUser;
  List<DocumentSnapshot> users = [];
  bool isLoading = true;
  bool reachDailyLimit = false;

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

    return allDocs;
  }

  Future<void> _loadUsers() async {
    if (user == null) return;
    final currentUserId = user!.uid;
    final now = DateTime.now();
    final todayKey = DateFormat('yyyyMMdd').format(now);

    final matchDocRef = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .collection('dailyMatches')
        .doc(todayKey);

    try {
      print('[Step 0] 取得當日配對快取');
      final matchDoc = await matchDocRef.get();

      if (matchDoc.exists) {
        print('[Step 0] 快取存在，讀取資料');
        final data = matchDoc.data() ?? {};
        final userIds = List<String>.from(data['userIds'] ?? []);
        reachDailyLimit = data['ReachDailyLimit'] == true;

        if (reachDailyLimit) {
          setState(() {
            users = [];
            isLoading = false;
          });
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('今日配對上限已到，請明天再來！')),
            );
          }
          print('[Step 0] 今日配對已達上限，結束');
          return;
        }

        if (userIds.isEmpty) {
          setState(() {
            users = [];
            isLoading = false;
          });
          print('[Step 0] 快取中 userIds 為空，結束');
          return;
        }

        final userDocs = await _batchedUserDocsByIds(userIds);
        setState(() {
          users = userDocs;
          isLoading = false;
        });
        print('[Step 0] 從快取載入使用者完成，結束');
        return;
      }
    } catch (e, st) {
      print('[Error Step 0] 讀取當日配對快取失敗: $e');
      print(st);
    }

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
    int likedMeCount = 0;
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
            doc.id != currentUserId
        ).toList();

        print('[Step 3] 過濾後按愛心使用者數量: ${likedMeUsers.length}');

        likedMeCount = min(5, likedMeUsers.length);
        likedMeUsers = likedMeUsers.take(5).toList();

        for (var doc in likedMeUsers) {
          print('[Step 3] LikedMeUserId: ${doc.id}');
        }
      }
    } catch (e, st) {
      print('[Error Step 3] 取得按愛心使用者資料失敗: $e');
      print(st);
    }

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

          if (matchSameDepartment == false && isSameDepartment) {
            return false; // 排除同系所
          }

          return !isSelf && !isPushed;
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
    Set<String> filteredUserIds = {};
    int filteredUserCount = 0;
    try {
      print('[Step 5] 挑出 tag 及 habit 傾向者');
      filteredUsers = allCandidateDocs
          .where((doc) =>
              !likedMeUsers.map((d) => d.id).contains(doc.id) &&
              ((doc['tags'] as List).any((tag) => topTags.contains(tag)) ||
              (doc['habits'] as List).any((habit) => topHabits.contains(habit))))
          .take(10) // 原本是15，因debug而改為10
          .toList();

      filteredUserCount = filteredUsers.length;
      filteredUserIds = filteredUsers.map((doc) => doc.id).toSet();
      print('[Step 5] 過濾後候選人數量: ${filteredUsers.length}');

      for (var doc in filteredUsers) {
        print('[Step 5] FilteredUser: ${doc.id} - ${doc['name']}');
      }
    } catch (e, st) {
      print('[Error Step 5] 過濾 tag/habit 使用者失敗: $e');
      print(st);
    }

    // 6. 從剩下的中隨機選擇
    List<DocumentSnapshot> randomUsers = [];
    List<DocumentSnapshot> randomSelection = [];
    try {
      print('[Step 6] 從剩餘候選人隨機選擇');
      randomUsers = allCandidateDocs
          .where((doc) =>
              !likedMeUsers.map((d) => d.id).contains(doc.id) &&
              !filteredUserIds.contains(doc.id))
          .toList()
        ..shuffle();
      randomSelection = randomUsers.take(25 - likedMeCount - filteredUserCount).toList();
      print('[Step 6] 隨機選擇人數: ${randomSelection.length}');

      for (var doc in randomSelection) {
        print('[Step 6] RandomSelection: ${doc.id} - ${doc['name']}');
      }
    } catch (e, st) {
      print('[Error Step 6] 隨機選擇使用者失敗: $e');
      print(st);
    }

    // 7. 合併推薦名單
    final recommendedUsers = [...likedMeUsers, ...filteredUsers, ...randomSelection];
    print('[Step 7] 合併推薦名單數量: ${recommendedUsers.length}');

    setState(() {
      users = recommendedUsers;
      isLoading = false;
    });

    // 8. 記錄 pushed
    try {
      print('[Step 8] 記錄 pushed');
      for (var doc in recommendedUsers) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUserId)
            .collection('pushed')
            .doc(doc.id)
            .set({'pushedAt': FieldValue.serverTimestamp()});
        print('[Step 8] 記錄 userId ${doc.id}');
      }
    } catch (e, st) {
      print('[Error Step 8] 記錄 pushed 失敗: $e');
      print(st);
    }

    // 9. 快取每日推薦
    try {
      print('[Step 9] 快取每日推薦');
      await matchDocRef.set({
        'createdAt': FieldValue.serverTimestamp(),
        'userIds': recommendedUsers.map((doc) => doc.id).toList(),
        'ReachDailyLimit': false,
      });
      print('[Step 9] 快取每日推薦完成');
    } catch (e, st) {
      print('[Error Step 9] 快取每日推薦失敗: $e');
      print(st);
    }
  }

  // ...existing code...

  Future<void> _showNextUser() async {
    if (users.isNotEmpty) {
      setState(() {
        users.removeAt(0);
      });
    }
    if (users.isEmpty) {
      setState(() {
        reachDailyLimit = true;
      });
      final currentUserId = user!.uid;
      final todayKey = DateFormat('yyyyMMdd').format(DateTime.now());
      final matchDocRef = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUserId)
          .collection('dailyMatches')
          .doc(todayKey);
      await matchDocRef.update({'ReachDailyLimit': true});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('今日配對上限已到，請明天再來！')),
        );
      }
    }
  }
  
  Future<void> _handleLike(String targetUserId) async {
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
      }());

      // 發送推播通知
      // sendPushNotification(targetUserId, '配對成功！');

      // 彈窗關閉後才換下一個人
      _showNextUser();
    } else {
      _showNextUser();
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

    // 你可以在這裡實作記錄不喜歡的邏輯，例如加入一個 dislikes collection
    _showNextUser();
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
                'assets/photo.png',
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
        'lastMessage': '',
        'lastMessageTime': FieldValue.serverTimestamp(),

        // 對每個成員儲存對方的名字
        'displayNames': {
          userA: userBName,
          userB: userAName,
        },
        'displayPhotos': {
          userA: userBDoc.data()?['photoUrl'] ?? '',
          userB: userADoc.data()?['photoUrl'] ?? '',
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
    if(reachDailyLimit) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/airplane.png',
              width: 120, // 依需求調整大小
              height: 120,
            ),
            const SizedBox(height: 16), // 圖片與文字間距
            const Text(
              '今日已達到配對上限',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ],
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
    const tagBoxWidth = 104.0;
    const tagBoxHeight = 39.0;
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
              ? ((users[0].data() as Map)['tags'] as List<dynamic>? ?? [])
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
                    ? () => _showUserDetail(context, users[0].data() as Map)
                    : null,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: users.isNotEmpty && (users[0].data() as Map)['photoUrl'] != null && (users[0].data() as Map)['photoUrl'].toString().isNotEmpty
                        ? Image.network(
                            (users[0].data() as Map)['photoUrl'],
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
                  child: Text(
                    users.isNotEmpty
                        ? (users[0].data() as Map)['name'] ?? '名字'
                        : '名字',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                ),
              ),
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
                  child: Text(
                    tags[i].toString(),
                    style: const TextStyle(
                      color: Colors.pink,
                      fontWeight: FontWeight.w500,
                      fontSize: 16,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),

              //叉叉按鈕
              Positioned(
                left: bgLeft + bgWidth * (45.0 / figmaWidth),
                top: bgTop + bgHeight * (701.0 / figmaHeight),
                width: bgWidth * (124.0 / figmaWidth),
                height: bgWidth * (124.0 / figmaWidth), // 用寬度比例確保圓形
                child: GestureDetector(
                  onTap: users.isNotEmpty ? () => _handleDislike(users[0].id) : null,
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
                  onTap: users.isNotEmpty ? () => _handleLike(users[0].id) : null,
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
                        'assets/heart.png',
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


  void _showUserDetail(BuildContext context, Map userData) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) {
      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 頭像
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: userData['photoUrl'] != null && userData['photoUrl'].toString().isNotEmpty
                    ? Image.network(
                        userData['photoUrl'],
                        width: 120,
                        height: 120,
                        fit: BoxFit.cover,
                      )
                    : Image.asset(
                        'assets/match_default.jpg',
                        width: 120,
                        height: 120,
                        fit: BoxFit.cover,
                      ),
              ),
              const SizedBox(height: 16),
              // 名字
              Text(
                userData['name'] ?? '',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              // 學校
              if (userData['school'] != null)
                Text(
                  userData['school'],
                  style: const TextStyle(fontSize: 16, color: Colors.grey),
                ),
              const SizedBox(height: 8),
              // 標籤
              if (userData['tags'] != null && userData['tags'] is List)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: (userData['tags'] as List)
                      .take(10)
                      .map<Widget>((tag) => Chip(
                            label: Text(tag.toString()),
                            backgroundColor: Colors.pink.shade50,
                          ))
                      .toList(),
                ),
              // 你可以根據 userData 增加更多欄位（MBTI、星座、興趣等）
            ],
          ),
        ),
      );
    },
  );
}
}