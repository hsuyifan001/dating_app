import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart'; // 用來格式化日期，需在pubspec.yaml加入 intl 套件
import 'package:auto_size_text/auto_size_text.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';

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

  bool _hasShownDialog = false; // 加入為 State 成員變數，防止重複彈出
  bool _hasLoaded = false;

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

    Map<String, dynamic>? firstUnseenActivity;
    String? currentActivityId;

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final likedBy = List<String>.from(data['likedBy'] ?? []);
      final dislikedBy = List<String>.from(data['dislikedBy'] ?? []);
      final hasInGroupChat = List<String>.from(data['hasInGroupChat'] ?? []);

      if (!likedBy.contains(uid) &&
          !dislikedBy.contains(uid) &&
          !hasInGroupChat.contains(uid)) {
        firstUnseenActivity = data;
        currentActivityId = doc.id;
        break;
      }
    }

    setState(() {
      activity = firstUnseenActivity;
      activityId = currentActivityId;
      _hasLoaded = true;
    });
  }


  Future<void> _showCreateActivityDialog() async {
    final _formKey = GlobalKey<FormState>();
    String? title;
    String? location;
    DateTime? dateTime;
    String? description;
    int? numberToCreateGroup;
    int? numberOfPeopleInGroup;
    XFile? pickedImage;
    String? imageUrl;

    final ImagePicker picker = ImagePicker();

    await showDialog(
      context: context,
      builder: (context) {

        return StatefulBuilder(
          builder: (context, setState) {
            Future<void> _pickImage() async {
              final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70); // 壓縮
              if (image != null) {
                setState(() {
                  pickedImage = image;
                });
              }
            }

            Future<void> _pickDateTime() async {
              final now = DateTime.now();
              final date = await showDatePicker(
                context: context,
                initialDate: now,
                firstDate: now,
                lastDate: DateTime(now.year + 1),
              );
              if (date != null) {
                final time = await showTimePicker(
                  context: context,
                  initialTime: TimeOfDay.now(),
                );
                if (time != null) {
                  setState(() {
                    dateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                  });
                }
              }
            }

            return AlertDialog(
              title: const Text('創建活動'),
              content: SizedBox(
                width: 400,
                height: 500, // ✅ 固定 Dialog 高度
                child:SingleChildScrollView(
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
                        const SizedBox(height: 10),
                        // 活動圖片
                        Row(
                          children: [
                            pickedImage == null
                                ? const Text("尚未選擇圖片")
                                : Image.file(
                                    File(pickedImage!.path),
                                    width: 80,
                                    height: 80,
                                    fit: BoxFit.cover,
                                  ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: _pickImage,
                              child: const Text("選擇圖片"),
                            )
                          ],
                        ),
                        const SizedBox(height: 10),
                        // 活動地點
                        TextFormField(
                          decoration: const InputDecoration(labelText: '地點'),
                          validator: (value) =>
                              value == null || value.isEmpty ? '請輸入地點' : null,
                          onSaved: (value) => location = value,
                        ),
                        const SizedBox(height: 10),
                        // 活動時間 Picker
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                dateTime == null
                                    ? "尚未選擇時間"
                                    : "${dateTime!.year}-${dateTime!.month}-${dateTime!.day} ${dateTime!.hour}:${dateTime!.minute.toString().padLeft(2, '0')}",
                              ),
                            ),
                            ElevatedButton(
                              onPressed: _pickDateTime,
                              child: const Text("選擇時間"),
                            )
                          ],
                        ),
                        const SizedBox(height: 10),
                        // 活動說明 ✅ 改這裡
                        SizedBox(
                          height: 100, // 限制輸入框高度
                          width: 400,
                          child: TextFormField(
                            decoration: const InputDecoration(labelText: '活動說明'),
                            onSaved: (value) => description = value,
                            keyboardType: TextInputType.multiline,
                            maxLines: null,   // 允許多行
                            expands: true,    // 填滿 SizedBox
                            maxLength: 200,   // 限制200字
                            validator: (value) {
                              if (value != null && value.length > 200) {
                                return '活動說明不能超過200字';
                              }
                              return null;
                            },
                          ),
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
              ),
              actions: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      child: const Text('取消'),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    TextButton(
                      child: const Text('我的活動'),
                      onPressed: () {
                        final userId = FirebaseAuth.instance.currentUser?.uid;
                        if (userId == null) return;

                        final todayKey = DateFormat("yyyyMMdd").format(DateTime.now());
                        final userActivityRef = FirebaseFirestore.instance
                            .collection("users")
                            .doc(userId)
                            .collection("activity")
                            .doc(todayKey);

                        showDialog(
                          context: context,
                          builder: (_) {
                            return AlertDialog(
                              title: const Text("我的活動"),
                              content: SizedBox(
                                width: double.maxFinite,
                                height: 300,
                                child: StreamBuilder<DocumentSnapshot>(
                                  stream: userActivityRef.snapshots(),
                                  builder: (context, snapshot) {
                                    if (!snapshot.hasData) {
                                      return const Center(child: CircularProgressIndicator());
                                    }

                                    final data = snapshot.data?.data() as Map<String, dynamic>?;
                                    final activityIds = (data?["activityIds"] as List?) ?? [];

                                    if (activityIds.isEmpty) {
                                      return const Center(child: Text("今天還沒有活動"));
                                    }

                                    return ListView.builder(
                                      itemCount: activityIds.length,
                                      itemBuilder: (context, index) {
                                        final activityId = activityIds[index];
                                        return FutureBuilder<DocumentSnapshot>(
                                          future: FirebaseFirestore.instance
                                              .collection("activities")
                                              .doc(activityId)
                                              .get(),
                                          builder: (context, activitySnap) {
                                            if (!activitySnap.hasData) {
                                              return const ListTile(
                                                  title: Text("載入中..."));
                                            }
                                            final actData =
                                                activitySnap.data?.data() as Map<String, dynamic>?;
                                            if (actData == null) {
                                              return const ListTile(
                                                  title: Text("活動已刪除"));
                                            }
                                            return ListTile(
                                              title: Text(actData["title"] ?? "未命名活動"),
                                              subtitle: Text(actData["location"] ?? ""),
                                              trailing: IconButton(
                                                icon: const Icon(Icons.delete),
                                                onPressed: () async {
                                                  // 刪掉活動文件
                                                  await FirebaseFirestore.instance
                                                      .collection("activities")
                                                      .doc(activityId)
                                                      .delete();

                                                  // 從使用者紀錄中移除
                                                  await userActivityRef.set({
                                                    "activityIds":
                                                        FieldValue.arrayRemove([activityId])
                                                  }, SetOptions(merge: true));

                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(content: Text("已刪除活動")),
                                                  );
                                                },
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),

                    ElevatedButton(
                      child: const Text('儲存'),
                      onPressed: () async {
                        if (_formKey.currentState?.validate() ?? false) {
                          _formKey.currentState?.save();

                          final userCreate = FirebaseAuth.instance.currentUser?.uid;
                          if (userCreate == null) {
                            Navigator.of(context).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('您尚未登入')));
                            return;
                          }

                          // 檢查是否超過每日限制
                          final todayKey =
                              DateFormat("yyyyMMdd").format(DateTime.now());
                          final userActivityRef = FirebaseFirestore.instance
                              .collection("users")
                              .doc(userCreate)
                              .collection("activity")
                              .doc(todayKey);

                          final snapshot = await userActivityRef.get();
                          final createdList =
                              (snapshot.data()?["activityIds"] as List?) ?? [];

                          if (createdList.length >= 3) {
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text("每天最多創建 3 個活動")));
                            return;
                          }

                          // 上傳圖片
                          if (pickedImage != null) {
                            final ref = FirebaseStorage.instance
                                .ref()
                                .child("activityImages/${DateTime.now().millisecondsSinceEpoch}.jpg");
                            await ref.putFile(File(pickedImage!.path));
                            imageUrl = await ref.getDownloadURL();
                          }

                          final docRef = FirebaseFirestore.instance
                              .collection('activities')
                              .doc();

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

                          // 記錄到使用者 activity 清單
                          await userActivityRef.set({
                            "activityIds": FieldValue.arrayUnion([docRef.id])
                          }, SetOptions(merge: true));

                          Navigator.of(context).pop();

                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('活動已創建')));
                          _loadActivity();
                        }
                      },
                    )
                  ],
                ),
              ],
            );
          },
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
          insetPadding: EdgeInsets.zero, // 移除預設邊距以便精確控制
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
          if (likedBy.length + 1 >= numberOfPeopleInGroup) {
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
            
            if (likedBy.length + 1 >= numberOfPeopleInGroup) {
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
    
    // 如果 activity 為 null 且尚未顯示過 Dialog，稍後彈出 Dialog
    if (_hasLoaded && activity == null && !_hasShownDialog) {
      // 延遲一點時間等 build 完成後再彈 (避免 setState During build)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showMatchSuccessDialog(context);
        setState(() {
          _hasShownDialog = true;
        });
      });
    }

    final String imageUrl = activity?['imageUrl'] ?? '';
    final String title = activity?['title'] ?? '';
    final timestamp = activity?['date'];
    final String source = activity?['source'] ?? '';
    final String url = activity?['url'] ?? '';
    final String description = activity?['description'] ?? '';
    final String location = activity?['location'] ?? '';

    // 判斷 timestamp 是否為 Timestamp 並轉成 DateTime
    DateTime? dateTime;
    if (timestamp != null) {
      dateTime = (timestamp as Timestamp).toDate();
    }
    // 格式化日期格式，可自訂格式
    final date = dateTime != null 
    ? DateFormat('yyyy-MM-dd HH:mm').format(dateTime) 
    : '';

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
          double baseFontSize = MediaQuery.of(context).size.width < 360 ? 14 : 18;


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
                  child:FittedBox(
                    fit: BoxFit.scaleDown,
                    child: const Text(
                      "創建活動",
                      style: const TextStyle(
                        fontFamily: 'Kiwi Maru',
                        fontWeight: FontWeight.w500,
                        fontSize: 20,
                        color: Colors.black,
                      ),
                      overflow: TextOverflow.ellipsis,

                    ),
                  )
                  
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
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          // 網路圖片抓取失敗時，顯示預設圖片
                          return Image.asset(
                            'assets/activity_default.png',
                            fit: BoxFit.contain,
                          );
                        },
                      ),
              ),

              Positioned(
                left: fx(0),  // 適當調整
                top: fy(530),
                width: fw(424),
                height: fh(217),
                child: Stack(
                  children: [
                    Image.asset(
                      "assets/activity_detail.png",
                      fit: BoxFit.fill,
                      width: fw(424),
                      height: fh(217),
                    ),
                    // 文字區容器，限定寬高以確保滾動範圍
                    Positioned(
                      left: fw(40),
                      top: fh(30),
                      width: fw(350), 
                      height: fh(157),  // 略小於整體高度留下padding
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          
                          children: [
                            // 使用 AutoSizeText 替代 Text，方便縮放字體
                            if (title.isNotEmpty)
                              AutoSizeText(
                                title,
                                style: TextStyle(fontSize: baseFontSize,fontWeight: FontWeight.bold),
                                minFontSize: 8,
                                maxFontSize: baseFontSize,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            if (date.isNotEmpty)
                              AutoSizeText(
                                '日期：$date',
                                style:  TextStyle(fontSize: baseFontSize, fontWeight: FontWeight.w500),
                                maxLines: 1,
                                minFontSize: 10,
                                maxFontSize: baseFontSize,
                              ),
                            if (source.isNotEmpty)
                              AutoSizeText(
                                '來源：$source',
                                style: TextStyle(fontSize: baseFontSize, fontWeight: FontWeight.w500),
                                maxLines: 1,
                                minFontSize: 10,
                                maxFontSize: baseFontSize,
                              ),
                            if (location.isNotEmpty)
                              AutoSizeText(
                                '地點：$location',
                                style: TextStyle(fontSize: baseFontSize, fontWeight: FontWeight.w500),
                                maxLines: 1,
                                minFontSize: 10,
                                maxFontSize: baseFontSize,
                              ),
                            if (description.isNotEmpty)
                              AutoSizeText(
                                '說明：$description',
                                style: TextStyle(fontSize: baseFontSize, fontWeight: FontWeight.w500),
                                minFontSize: 10,
                                maxFontSize: baseFontSize,
                              ),
                            const SizedBox(height: 6),
                            if (url.isNotEmpty)
                              GestureDetector(
                                behavior: HitTestBehavior.translucent,
                                onTap: () => _launchURL(context, url),
                                child: AutoSizeText(
                                  '更多資訊連結',
                                  style: TextStyle(
                                    fontSize: baseFontSize,
                                    color: Colors.blue,
                                    decoration: TextDecoration.underline,
                                  ),
                                  minFontSize: 10,
                                  maxFontSize: baseFontSize,
                                ),
                              ),
                          ],
                        ),
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
                    border: Border.all(color: const Color.fromRGBO(129, 189, 195, 1), width: 3),
                  ),
                  child: Center(
                    child: AutoSizeText(
                      "  "+title,
                      style: const TextStyle(
                        fontFamily: 'Kiwi Maru',
                        fontWeight: FontWeight.w500,
                        fontSize: 25,
                        color: Colors.black,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      minFontSize: 12,   // 設定字體縮放的最小尺寸，避免裁切
                    ),
                  ),
                ),
              ),

              // 愛心按鈕
              Positioned(
                left: fx(244.14),
                top: fy(744.04),
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
                top: fy(744.04),
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
