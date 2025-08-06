import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; // for DateFormat

class MatchPage extends StatefulWidget {
  const MatchPage({super.key});

  @override
  State<MatchPage> createState() => _MatchPageState();
}

class _MatchPageState extends State<MatchPage> {
  final user = FirebaseAuth.instance.currentUser;
  List<DocumentSnapshot> users = [];
  bool isLoading = true;

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

  final matchDoc = await matchDocRef.get();

  if (matchDoc.exists) {
    final data = matchDoc.data() ?? {};
    final userIds = List<String>.from(data['userIds'] ?? []);
    final reachDailyLimit = data['ReachDailyLimit'] == true;

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
      return;
    }

    if (userIds.isEmpty) {
      setState(() {
        users = [];
        isLoading = false;
      });
      return;
    }

    final userDocs = await _batchedUserDocsByIds(userIds);

    setState(() {
      users = userDocs;
      isLoading = false;
    });
    return;
  }

  // 1. 取得已推播過的 userId
  final pushedSnapshot = await FirebaseFirestore.instance
      .collection('users')
      .doc(currentUserId)
      .collection('pushed')
      .get();
  final pushedIds = pushedSnapshot.docs.map((doc) => doc.id).toSet();

  // 2. 取得自己的配對條件與 likedTagCount 及 likedHabitCount
  final currentUserDoc = await FirebaseFirestore.instance
      .collection('users')
      .doc(currentUserId)
      .get();
  final currentUserData = currentUserDoc.data() ?? {};
  final currentUserDepartment = currentUserData['department'] ?? '';
  final matchSameDepartment = currentUserData['matchSameDepartment'] ?? false;
  final matchGender = List<String>.from(currentUserData['matchGender'] ?? []);
  final matchSchools = List<String>.from(currentUserData['matchSchools'] ?? []);
  final likedTagCount = Map<String, int>.from(currentUserData['likedTagCount'] ?? {});
  final likedHabitCount = Map<String, int>.from(currentUserData['likedHabitCount'] ?? {});

  // 計算 top 3 tag 及 top 3 habit
  final sortedTags = likedTagCount.keys.toList()
    ..sort((a, b) => likedTagCount[b]!.compareTo(likedTagCount[a]!));
  final topTags = sortedTags.take(3).toList();
  final sortedHabits = likedHabitCount.keys.toList()
    ..sort((a, b) => likedHabitCount[b]!.compareTo(likedHabitCount[a]!));
  final topHabits = sortedHabits.take(3).toList();

  // 3. 對你按過愛心的人
  final likedMeSnapshot = await FirebaseFirestore.instance
      .collection('likes')
      .where('to', isEqualTo: currentUserId)
      .get();
  final likedMeIds = likedMeSnapshot.docs.map((doc) => doc['from'] as String).toSet();

  List<DocumentSnapshot> likedMeUsers = [];
  if (likedMeIds.isNotEmpty) {
    final allDocs = await _batchedUserDocsByIds(likedMeIds.toList());
    likedMeUsers = allDocs
        .where((doc) =>
            matchGender.contains(doc['gender']) &&
            !pushedIds.contains(doc.id) &&
            doc.id != currentUserId)
        .take(5)
        .toList();
  }
  final likedMeUserIds = likedMeUsers.map((doc) => doc.id).toSet();

  // 4. 查詢一次所有候選人（符合性別、學校、系所且未被推播）
  final allCandidateSnapshot = await FirebaseFirestore.instance
      .collection('users')
      .where('gender', whereIn: matchGender)
      .where('school', whereIn: matchSchools)
      .get();
  final allCandidateDocs = allCandidateSnapshot.docs.where((doc) {
    final isSelf = doc.id == currentUserId;
    final isPushed = pushedIds.contains(doc.id);
    final isSameDepartment = doc['department'] == currentUserDepartment;

    if (matchSameDepartment == false && isSameDepartment) {
      return false; // 排除同系所
    }

    return !isSelf && !isPushed;
  }).toList();

  // 5. 從中挑出 tag 及 habit 傾向者
  final filteredUsers = allCandidateDocs
      .where((doc) =>
          !likedMeUserIds.contains(doc.id) &&
          ((doc['tags'] as List).any((tag) => topTags.contains(tag)) ||
           (doc['habits'] as List).any((habit) => topHabits.contains(habit))))
      .take(15)
      .toList();
  final filteredUserIds = filteredUsers.map((doc) => doc.id).toSet();

  // 6. 從剩下的中隨機選擇
  final randomUsers = allCandidateDocs
      .where((doc) =>
          !likedMeUserIds.contains(doc.id) &&
          !filteredUserIds.contains(doc.id))
      .toList()
    ..shuffle();
  final randomSelection = randomUsers.take(5).toList();

  // 7. 合併推薦名單
  final recommendedUsers = [...likedMeUsers, ...filteredUsers, ...randomSelection];

  setState(() {
    users = recommendedUsers;
    isLoading = false;
  });

  // 8. 記錄 pushed
  for (var doc in recommendedUsers) {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .collection('pushed')
        .doc(doc.id)
        .set({'pushedAt': FieldValue.serverTimestamp()});
  }

  // 9. 快取每日推薦
  await matchDocRef.set({
    'createdAt': FieldValue.serverTimestamp(),
    'userIds': recommendedUsers.map((doc) => doc.id).toList(),
    'ReachDailyLimit': false,
  });
}

  // ...existing code...

  Future<void> _showNextUser() async {
    if (users.isNotEmpty) {
      setState(() {
        users.removeAt(0);
      });
      // 如果移除後已經沒有使用者，則標記 ReachDailyLimit 為 true
      if (users.isEmpty) {
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
    } else {
      // 若一開始就為空，也顯示今日上限已到
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

    if (reverseLike.exists) {
      final matchId = currentUserId.compareTo(targetUserId) < 0
          ? '${currentUserId}_$targetUserId'
          : '${targetUserId}_$currentUserId';

      await firestore.collection('matches').doc(matchId).set({
        'user1': currentUserId,
        'user2': targetUserId,
        'matchedAt': FieldValue.serverTimestamp(),
      });

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('🎉 配對成功！')),
        ).closed.then((_) {
          _showNextUser();
        });
      }
    } else {
      _showNextUser();
    }
  }

  Future<void> _handleDislike(String targetUserId) async {
    // 你可以在這裡實作記錄不喜歡的邏輯，例如加入一個 dislikes collection
    _showNextUser();
  }


  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
  
    // Figma 畫布尺寸
    const figmaWidth = 412.0;
    const figmaHeight = 917.0;
  
    // 名字方框在 figma 的位置與大小
    const nameBoxLeft = 45.0;
    const nameBoxTop = 480.0;
    const nameBoxWidth = 128.0;
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