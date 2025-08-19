import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';

class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  final String detailContent = "這裡是活動詳細內容...";

  // Figma 畫布尺寸
  final double figmaWidth = 412.0;
  final double figmaHeight = 917.0;

  Map<String, dynamic>? activity; // 存放要顯示的活動
  String? activityId;

  @override
  void initState() {
    super.initState();
    _loadActivity();
  }

  Future<void> _loadActivity() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final snapshot = await FirebaseFirestore.instance
        .collection('activities')
        .get();

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final likedBy = List<String>.from(data['likedBy'] ?? []);
      final dislikedBy = List<String>.from(data['dislikedBy'] ?? []);
      final hasInGroupChat = List<String>.from(data['hasInGroupChat'] ?? []);

      if (!likedBy.contains(uid) &&
          !dislikedBy.contains(uid) &&
          !hasInGroupChat.contains(uid)) {
        setState(() {
          activity = data;
          activityId = doc.id;
        });
        break;
      }
    }
  }

  Future<void> _showCreateActivityDialog() async {
    final _formKey = GlobalKey<FormState>();
    String? title;
    String? imageUrl;
    String? location;
    DateTime? dateTime;
    String? description;
    int? numberToCreateGroup;
    int? numberOfPeopleInGroup;

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('創建活動'),
          content: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 活動名稱
                  TextFormField(
                    decoration: const InputDecoration(labelText: '活動名稱'),
                    validator: (value) =>
                        value == null || value.isEmpty ? '請輸入活動名稱' : null,
                    onSaved: (value) => title = value,
                  ),
                  // 活動圖片 URL（簡化用 URL 輸入）
                  TextFormField(
                    decoration: const InputDecoration(labelText: '圖片 URL'),
                    onSaved: (value) => imageUrl = value,
                  ),
                  // 活動地點
                  TextFormField(
                    decoration: const InputDecoration(labelText: '地點'),
                    validator: (value) =>
                        value == null || value.isEmpty ? '請輸入地點' : null,
                    onSaved: (value) => location = value,
                  ),
                  // 活動時間 Picker（簡化為文字輸入，推薦後續改用 DateTimePicker）
                  TextFormField(
                    decoration: const InputDecoration(labelText: '時間(yyyy-MM-dd HH:mm)'),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '請輸入時間';
                      }
                      try {
                        dateTime = DateTime.parse(value);
                      } catch (e) {
                        return '時間格式錯誤';
                      }
                      return null;
                    },
                  ),
                  // 活動說明
                  TextFormField(
                    decoration: const InputDecoration(labelText: '活動說明'),
                    onSaved: (value) => description = value,
                    maxLines: 3,
                  ),
                  // 建立群組人數
                  TextFormField(
                    decoration: const InputDecoration(labelText: '建立群組人數'),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '請輸入建立群組人數';
                      }
                      final numVal = int.tryParse(value);
                      if (numVal == null || numVal <= 0) {
                        return '請輸入正確的數字';
                      }
                      return null;
                    },
                    onSaved: (value) =>
                        numberToCreateGroup = int.tryParse(value ?? ''),
                  ),
                  // 活動人數上限
                  TextFormField(
                    decoration: const InputDecoration(labelText: '活動人數上限'),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return '請輸入活動人數上限';
                      }
                      final numVal = int.tryParse(value);
                      if (numVal == null || numVal <= 0) {
                        return '請輸入正確的數字';
                      }
                      return null;
                    },
                    onSaved: (value) =>
                        numberOfPeopleInGroup = int.tryParse(value ?? ''),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              child: const Text('取消'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: const Text('儲存'),
              onPressed: () async {
                if (_formKey.currentState?.validate() ?? false) {
                  _formKey.currentState?.save();

                  // 取得目前使用者 ID 作為創建者
                  final userCreate = FirebaseAuth.instance.currentUser?.uid;
                  if (userCreate == null) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('您尚未登入')));
                    return;
                  }

                  final docRef = FirebaseFirestore.instance.collection('activities').doc();

                  await docRef.set({
                    "createdAt": FieldValue.serverTimestamp(),
                    "date": dateTime,
                    "imageUrl": imageUrl ?? '',
                    "title": title ?? '',
                    "url": null,
                    "source": 'user',
                    "likedBy": [userCreate],
                    "dislikedBy": [],
                    "hasInGroupChat": [],
                    "NumberToCreateGroup": numberToCreateGroup ?? 1,
                    "NumberOfPeopleInGroup": numberOfPeopleInGroup ?? 1,
                    "groupId": null,
                    "location": location ?? '',
                    "description": description ?? '',
                  });

                  Navigator.of(context).pop();

                  // 重新載入活動列表或給予提示
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('活動已創建')));
                  _loadActivity();
                }
              },
            )
          ],
        );
      },
    );
  }

  Future<void> _dislikeActivity() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || activityId == null) return;

    await FirebaseFirestore.instance
        .collection('activities')
        .doc(activityId)
        .update({
      "dislikedBy": FieldValue.arrayUnion([uid]),
    });

    // 更新完之後再載入下一個活動
    setState(() {
      activity = null;
      activityId = null;
    });
    _loadActivity();
  }
  
  Future<void> showMatchSuccessDialog(BuildContext context) async {
    await showDialog(
      context: context,
      barrierDismissible: true, // 點擊背景關閉
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.only(left: 25, top: 248, right: 24, bottom: 24),
          child: SizedBox(
            width: 363,
            height: 253,
            child: Stack(
              children: [
                Opacity(
                  opacity: 1,
                  child: Image.asset(
                    'assets/match_success.png',
                    width: 363,
                    height: 253,
                    fit: BoxFit.contain,
                  ),
                ),
                
              ],
            ),
          ),
        );
      },
    );
  }


  Future<void> _likeActivity() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || activity == null || activityId == null) return;

      final source = activity!['source'] ?? '';
      final groupId = activity!['groupId'];
      final likedBy = List<String>.from(activity!['likedBy'] ?? []);
      final numberOfPeopleInGroup = activity!['NumberOfPeopleInGroup'] ?? 0;
      final numberToCreateGroup = activity!['NumberToCreateGroup'] ?? 0;

      // 檢查是否為 user 建立的活動
      if (source == 'user') {
        // 檢查 groupId 是否為 null
        if (groupId != null) {
          
          // 把使用者加入 chats/groupId/members 陣列
          final groupChatRef = FirebaseFirestore.instance.collection('chats').doc(groupId);
          await groupChatRef.update({
            'members': FieldValue.arrayUnion([uid])
          });

          // 判斷自己是不是最後一個可加入群組的人
          if (likedBy.length + 1 == numberOfPeopleInGroup) {
            // 刪除該活動文件
            await FirebaseFirestore.instance
                .collection('activities')
                .doc(activityId)
                .delete();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('您是最後一位加入，活動已從列表刪除')),
            );
          }
          //未達人數上限不用做事
          else{
          }
          await showMatchSuccessDialog(context);

        }
        //groupId 為 null 
        else{
          // 把使用者加入活動的 likedBy 陣列
          await FirebaseFirestore.instance
              .collection('activities')
              .doc(activityId)
              .update({
            "likedBy": FieldValue.arrayUnion([uid]),
          });

          //是否達到創建群組的調件
          if(likedBy.length + 1 >= numberToCreateGroup){
            // 創建新的群組
            final newGroupRef = FirebaseFirestore.instance.collection('chats').doc();
            await newGroupRef.set({
              'createdAt': FieldValue.serverTimestamp(),
              'members': [...likedBy, uid],
              'type': 'activity',
              'groupName': activity!['title'] ?? '活動群組',
              'groupPhotoUrl': activity!['imageUrl'] ?? '',
              'lastMessageTime' : FieldValue.serverTimestamp(),
              'lastMessage': '活動配對成功，請在群組中討論',
            });
            // 更新活動文件的 groupId
            await FirebaseFirestore.instance
                .collection('activities')
                .doc(activityId)
                .update({
              'groupId': newGroupRef.id,
            });
            
            if (likedBy.length + 1 == numberOfPeopleInGroup) {
              // 刪除該活動文件
              await FirebaseFirestore.instance
                  .collection('activities')
                  .doc(activityId)
                  .delete();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('您是最後一位加入，活動已從列表刪除')),
              );
            }
            await showMatchSuccessDialog(context);

            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('活動已加入喜歡列表並創建群組')),
            );
          }
          else{
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('活動已加入喜歡列表，但未達到創建群組的條件')),
            );
          }
        }
    }
    //source != 'user'
    else{
      // 把使用者加入 likedBy 陣列
      await FirebaseFirestore.instance
          .collection('activities')
          .doc(activityId)
          .update({
        "likedBy": FieldValue.arrayUnion([uid]),
      });
      // 如果達到創建群組條件
      if (likedBy.length + 1 >= numberToCreateGroup) {
        // 創建新的群組
        final newGroupRef = FirebaseFirestore.instance.collection('chats').doc();
        await newGroupRef.set({
          'createdAt': FieldValue.serverTimestamp(),
          'members': [...likedBy, uid], // 將 likedBy 全部成員搬移
          'type': 'activity',
          'groupName': activity!['title'] ?? '活動群組',
          'groupPhotoUrl': activity!['imageUrl'] ?? '',
          'lastMessageTime': FieldValue.serverTimestamp(),
          'lastMessage': '活動配對成功，請在群組中討論',
        });

        // 更新活動文件的 groupId 並且把 likedBy 轉移到 hasInGroupChat
        await FirebaseFirestore.instance
            .collection('activities')
            .doc(activityId)
            .update({
          'groupId': newGroupRef.id,
          'hasInGroupChat': FieldValue.arrayUnion(likedBy),
          'likedBy': [],
        });
        await showMatchSuccessDialog(context);

        ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('活動已加入喜歡列表並創建群組')));
      }
      else{
        ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('活動已加入喜歡列表')),
      );
      }
      
    }

    //做完事了
    setState(() {
      activity = null;
      activityId = null;
    });
    _loadActivity();
    return;
  }


  void _launchURL(BuildContext context, String url) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('無法開啟網址')),
      );
    }
  }
  @override
  Widget build(BuildContext context) {
    
    if (activity == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final String imageUrl = activity!['imageUrl'] ?? '';
    final String title = activity!['title'] ?? '';
    final String date = activity!['Date'] ?? '無日期資料';
    final String source = activity!['source'] ?? '無來源資料';
    final String url = activity!['url'] ?? '';



    return Scaffold(
      backgroundColor: const Color(0xFCD3F8F3),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final screenWidth = constraints.maxWidth;
          final screenHeight = constraints.maxHeight;

          // 計算背景圖呈現範圍
          final bgAspect = figmaWidth / figmaHeight;
          final screenAspect = screenWidth / screenHeight;

          double bgWidth, bgHeight, bgLeft, bgTop;
          if (screenAspect > bgAspect) {
            // 螢幕比較寬 → 高度填滿，上下對齊
            bgHeight = screenHeight;
            bgWidth = bgHeight * bgAspect;
            bgLeft = (screenWidth - bgWidth) / 2;
            bgTop = 35;
          } else {
            // 螢幕比較窄 → 寬度填滿，左右對齊
            bgWidth = screenWidth;
            bgHeight = bgWidth / bgAspect;
            bgLeft = 0;
            bgTop = (screenHeight - bgHeight) / 2+30;
          }

          // 封裝換算工具（把 Figma 上的座標轉成實際螢幕 px）
          double fw(double px) => bgWidth * (px / figmaWidth);
          double fh(double px) => bgHeight * (px / figmaHeight);
          double fx(double px) => bgLeft + bgWidth * (px / figmaWidth);
          double fy(double px) => bgTop + bgHeight * (px / figmaHeight);

          return Stack(
            children: [
              
              // 創建活動按鈕
              Positioned(
                left: fx(272),
                top: fy(10),
                width: fw(131),
                height: fh(48),
                child: ElevatedButton(
                  onPressed: _showCreateActivityDialog, // 觸發懸浮視窗
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color.fromRGBO(246, 219, 220, 1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: const BorderSide(color: Colors.black, width: 2),
                    ),
                  ),
                  child: const Text(
                    "創建活動",
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              // 活動圖片
              Positioned(
                left: fx(70),
                top: fy(110),
                width: fw(290),
                height: fh(340),
                child: imageUrl == null || imageUrl.isEmpty
                    ? Image.asset(
                        'assets/activity_default.png',
                        fit: BoxFit.contain,
                      )
                    : Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          // 網路圖片抓取失敗時，顯示預設圖片
                          return Image.asset(
                            'assets/activity_default.png',
                            fit: BoxFit.contain,
                          );
                        },
                      ),
              ),

              // 活動詳細內容背景 + 文字
              Positioned(
                left: fx(-2),
                top: fy(530),
                width: fw(424),
                height: fh(157),
                child: Stack(
                  children: [
                    Image.asset(
                      "assets/activity_detail.png",
                      fit: BoxFit.fill,
                      width: fw(424),
                      height: fh(157),
                    ),
                    Positioned(
                      left: fx(-60),
                      top: fy(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '活動名稱：$title',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                          ),
                          Text(
                            '日期：$date',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                          ),
                          
                          Text(
                            '來源：$source',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                          ),
                          const SizedBox(height: 6),
                          url.isNotEmpty
                              ? GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onTap: () => _launchURL(context, url),
                                  child: Text(
                                    '更多資訊連結',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: Colors.blue,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // 背景圖
              Positioned(
                left: bgLeft,
                top: bgTop,
                width: bgWidth,
                height: bgHeight,
                child: IgnorePointer(
                  child: Image.asset(
                    "assets/activity_background.png",
                    fit: BoxFit.contain,
                  ),
                ),
              ),

              // 活動名稱文字框
              Positioned(
                left: fx(181.09),
                top: fy(470),
                width: fw(218),
                height: fh(54),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color.fromRGBO(129, 189, 195, 1), width: 3),
                  ),
                  child: Center(
                    child: Text(
                      title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),

              // 愛心按鈕
              Positioned(
                left: fx(244.14),
                top: fy(694.04),
                width: fw(114.57),
                height: fh(112.72),
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
                  child: IconButton(
                    onPressed:  _likeActivity,
                    icon: Image.asset("assets/heart.png"),
                  ),
                ),
              ),

              // 叉叉按鈕
              Positioned(
                left: fx(56.57),
                top: fy(694.04),
                width: fw(114),
                height: fh(112),
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
                  child: IconButton(
                    onPressed:  _dislikeActivity,
                    icon: Image.asset("assets/no.png"),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
