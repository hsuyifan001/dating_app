import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  Future<void> _loadUsers() async {
    if (user == null) return;

    final snapshot = await FirebaseFirestore.instance.collection('users').get();
    final currentUserId = user!.uid;

    final filteredUsers = snapshot.docs.where((doc) => doc.id != currentUserId).toList();

    setState(() {
      users = filteredUsers;
      isLoading = false;
    });
  }

  Future<void> _showNextUser() async {
    if (users.isNotEmpty) {
      setState(() {
        users.removeAt(0);
      });
      // 如果移除後已經沒有使用者，則重新載入
      if (users.isEmpty) {
        await _loadUsers();
      }
    } else {
      // 若一開始就為空，也重新載入
      await _loadUsers();
    }
  }
  
  Future<void> _handleLike(String targetUserId) async {
    final currentUserId = user!.uid;
  
    await FirebaseFirestore.instance
        .collection('likes')
        .doc('$currentUserId\_$targetUserId')
        .set({
      'from': currentUserId,
      'to': targetUserId,
      'timestamp': FieldValue.serverTimestamp(),
    });
  
    final reverseLike = await FirebaseFirestore.instance
        .collection('likes')
        .doc('$targetUserId\_$currentUserId')
        .get();
  
    if (reverseLike.exists) {
      final matchId = currentUserId.compareTo(targetUserId) < 0
          ? '${currentUserId}_$targetUserId'
          : '${targetUserId}_$currentUserId';
  
      await FirebaseFirestore.instance.collection('matches').doc(matchId).set({
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
              // 背景圖片
              Positioned.fill(
                child: Image.asset(
                  'assets/match_background.png',
                  fit: BoxFit.contain,
                  alignment: Alignment.topCenter,
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
              for (int i = 0; i < 6; i++)
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
                      tags.length > i ? tags[i].toString() : '',
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

}