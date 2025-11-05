// story_page.dart
import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:timeago/timeago.dart' as timeago;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'dart:typed_data';


class StoryPage extends StatefulWidget {
  const StoryPage({Key? key}) : super(key: key);

  @override
  State<StoryPage> createState() => _StoryPageState();
}

class _StoryPageState extends State<StoryPage> {
  final currentUser = FirebaseAuth.instance.currentUser!;
  List<String> matchedUserIds = [];
  List<Map<String, dynamic>> allStories = [];
  bool hasStories = false;

  Map<String, Map<String, dynamic>> userInfoCache = {}; // 🔹 預先緩存使用者資料
  Map<String, bool> _updatingLikes = {}; // storyId => 是否正在更新
  
  //** 分頁載入控制
  final ScrollController _scrollController = ScrollController(); //**
  DocumentSnapshot? lastStoryDoc; //** 上次抓取的最後一個 story，用於分頁
  bool isLoadingMore = false; //** 是否正在加載更多 stories
  final int pageSize = 15; //** 每次抓取數量

  @override
  void initState() {
    super.initState();
    _loadMatchedUsers();
    //** 監聽滑動，自動分頁
    _scrollController.addListener(() {
      if (_scrollController.position.pixels >=
          _scrollController.position.maxScrollExtent - 200) {
        if (!isLoadingMore) _loadStories(loadMore: true);
      }
    }); //**
  }

  Future<void> _loadMatchedUsers() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .collection('matches')
        .get();

    matchedUserIds = snapshot.docs.map((doc) => doc.id).toList();
    matchedUserIds.add(currentUser.uid); // 包含自己

    await _loadStories();
  }


   //** 分頁抓取 Stories + 緩存使用者資料
  Future<void> _loadStories({bool loadMore = false}) async {
    if (isLoadingMore) return; //** 避免重複加載
    setState(() => isLoadingMore = true);

    List<Map<String, dynamic>> tempStories = [];

    //** Step1：預先抓取緩存使用者資料
    for (var uid in matchedUserIds) {
      if (!userInfoCache.containsKey(uid)) {
        final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        final data = userDoc.data() as Map<String, dynamic>?; //**
        userInfoCache[uid] = data ?? {}; //** 避免 null
      }
    }

    //** Step2：抓 stories 分頁
    for (var uid in matchedUserIds) {
      Query query = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('stories')
          .orderBy('timestamp', descending: true)
          .limit(pageSize);

      if (loadMore && lastStoryDoc != null) {
        query = query.startAfterDocument(lastStoryDoc!);
      }

      final storySnapshot = await query.get();
      if (storySnapshot.docs.isNotEmpty) {
        lastStoryDoc = storySnapshot.docs.last; //** 記錄最後一筆
      }

      for (var doc in storySnapshot.docs) {
        final data = doc.data() as Map<String, dynamic>?; //**
        if (data != null) { //** 避免 null
          data['storyId'] = doc.id;
          data['userId'] = uid;
          tempStories.add(data);
        }
      }
    }

    //** Step3：合併並排序
    final mergedStories = [...allStories, ...tempStories];
    mergedStories.sort((a, b) {
      final tsA = (a['timestamp'] as Timestamp?)?.toDate() ?? DateTime(2000);
      final tsB = (b['timestamp'] as Timestamp?)?.toDate() ?? DateTime(2000);
      return tsB.compareTo(tsA);
    });

    setState(() {
      allStories = mergedStories;
      hasStories = mergedStories.isNotEmpty;
      isLoadingMore = false;
    });
  }


void _openAddStoryDialog({String? storyId, Map<String, dynamic>? existingData}) async {
  final textController = TextEditingController(text: existingData?['text'] ?? '');
  final ImagePicker picker = ImagePicker();
  List<XFile> newImages = []; // 新選的圖片，尚未上傳
  List<String> uploadedImages = existingData?['photoUrls'] != null
      ? List<String>.from(existingData!['photoUrls'])
      : [];
  int step = 0; // 0 = 選圖片, 1 = 輸入文字
  final PageController pageController = PageController();
  int currentIndex = 0;

  await showDialog(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) {
        final screenHeight = MediaQuery.of(context).size.height;

        // 總圖片數（已上傳 + 新選）
        int totalImages = uploadedImages.length + newImages.length;

        return AlertDialog(
          title: Text(storyId == null ? '新增動態' : '編輯動態'),
          content: SizedBox(
            width: double.maxFinite,
            height: screenHeight * 0.5,
            child: Column(
              children: [
                Expanded(
                  child: totalImages == 0
                      ? Center(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final picked = await picker.pickMultiImage();
                              if (picked.isNotEmpty) {
                                setState(() => newImages = picked.take(10).toList());
                              }
                            },
                            icon: const Icon(Icons.photo_library),
                            label: const Text('選擇圖片'),
                          ),
                        )
                      : PageView.builder(
                          controller: pageController,
                          itemCount: totalImages + (totalImages < 10 ? 1 : 0),
                          onPageChanged: (index) => setState(() => currentIndex = index),
                          itemBuilder: (context, index) {
                            if (index < uploadedImages.length) {
                              // 已上傳圖片
                              final url = uploadedImages[index];
                              return Stack(
                                children: [
                                  Positioned.fill(
                                    child: Image.network(url, fit: BoxFit.contain),
                                  ),
                                  // 刪除叉叉
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: InkWell(
                                      onTap: () async {
                                        // 刪除 Storage 中的圖片
                                        try {
                                          final ref = FirebaseStorage.instance.refFromURL(url);
                                          await ref.delete();
                                        } catch (e) {
                                          print("刪除圖片失敗: $e");
                                        }
                                        setState(() {
                                          uploadedImages.removeAt(index);
                                          if (currentIndex >= uploadedImages.length + newImages.length) {
                                            currentIndex = uploadedImages.length + newImages.length - 1;
                                          }
                                        });
                                      },
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          shape: BoxShape.circle,
                                        ),
                                        padding: const EdgeInsets.all(4),
                                        child: const Icon(Icons.close, color: Colors.white, size: 20),
                                      ),
                                    ),
                                  ),
                                  // 頁數標記
                                  Positioned(
                                    top: 8,
                                    left: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        "${index + 1}/${totalImages}",
                                        style: const TextStyle(color: Colors.white, fontSize: 14),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            } else if (index < totalImages) {
                              // 新選圖片
                              final img = newImages[index - uploadedImages.length];
                              return Stack(
                                children: [
                                  Positioned.fill(
                                    child: Image.file(File(img.path), fit: BoxFit.contain),
                                  ),
                                  Positioned(
                                    top: 8,
                                    right: 8,
                                    child: InkWell(
                                      onTap: () {
                                        setState(() {
                                          newImages.removeAt(index - uploadedImages.length);
                                          if (currentIndex >= uploadedImages.length + newImages.length) {
                                            currentIndex = uploadedImages.length + newImages.length - 1;
                                          }
                                        });
                                      },
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.black54,
                                          shape: BoxShape.circle,
                                        ),
                                        padding: const EdgeInsets.all(4),
                                        child: const Icon(Icons.close, color: Colors.white, size: 20),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 8,
                                    left: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.black54,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        "${index + 1}/${totalImages}",
                                        style: const TextStyle(color: Colors.white, fontSize: 14),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            } else {
                              // 最後一頁：新增圖片
                              return Center(
                                child: ElevatedButton.icon(
                                  onPressed: totalImages < 10
                                      ? () async {
                                          final picked = await picker.pickMultiImage();
                                          if (picked.isNotEmpty) {
                                            setState(() {
                                              newImages.addAll(picked);
                                              if (newImages.length + uploadedImages.length > 10) {
                                                newImages = newImages.take(10 - uploadedImages.length).toList();
                                              }
                                            });
                                          }
                                        }
                                      : null,
                                  icon: const Icon(Icons.add),
                                  label: Text('新增圖片 (最多10張)'),
                                ),
                              );
                            }
                          },
                        ),
                ),
                if (step == 1 || totalImages > 0)
                  const SizedBox(height: 10),
                if (step == 1)
                  TextField(
                    controller: textController,
                    decoration: const InputDecoration(
                      hintText: '寫下文字內容...',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            if (step == 0)
              TextButton(
                onPressed: totalImages > 0 ? () => setState(() => step = 1) : null,
                child: const Text('下一步'),
              ),
            if (step == 1)
              TextButton(
                onPressed: () async {
                  Navigator.pop(context);
                  List<String> uploadedUrls = [...uploadedImages];

                  // 上傳新選圖片
                  for (var img in newImages) {
                    final Uint8List? compressedImage =
                        await FlutterImageCompress.compressWithFile(
                      img.path,
                      minWidth: 800,
                      minHeight: 800,
                      quality: 70,
                      format: CompressFormat.jpeg,
                    );

                    if (compressedImage == null) {
                      throw Exception('壓縮圖片失敗');
                    }

                    final ref = FirebaseStorage.instance.ref(
                      'story_images/${currentUser.uid}/${DateTime.now().millisecondsSinceEpoch}.jpg',
                    );

                    await ref.putData(
                      compressedImage,
                      SettableMetadata(contentType: 'image/jpeg'),
                    );

                    uploadedUrls.add(await ref.getDownloadURL());
                  }

                  final storyData = {
                    'text': textController.text.trim(),
                    'photoUrls': uploadedUrls,
                    'timestamp': FieldValue.serverTimestamp(),
                    'likes': existingData?['likes'] ?? [],
                    'comments': existingData?['comments'] ?? [],
                  };

                  final userStoriesRef = FirebaseFirestore.instance
                      .collection('users')
                      .doc(currentUser.uid)
                      .collection('stories');

                  if (storyId == null) {
                    await userStoriesRef.add(storyData);
                  } else {
                    await userStoriesRef.doc(storyId).update(storyData);
                  }

                  _loadStories();
                },
                child: const Text('發布'),
              ),
          ],
        );
      },
    ),
  );
}




  void _toggleLike(String userId, String storyId, List likes) async {
    /*final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('stories')
        .doc(storyId);*/

    final hasLiked = likes.contains(currentUser.uid);
    
    setState(() {
    if (hasLiked) {
      likes.remove(currentUser.uid);
    } else {
      likes.add(currentUser.uid);
    }
    // 更新本地資料，立即反應 UI
    final index = allStories.indexWhere((s) => s['storyId'] == storyId);
    allStories[index]['likes'] = List.from(likes);
    });

    // 🔹 非同步更新 Firebase
    _updateLikeInFirebase(userId, storyId, likes);
  }


  
  Future<void> _updateLikeInFirebase(String userId, String storyId, List<dynamic> likes) async {
    if (_updatingLikes[storyId] == true) return; // 正在更新中就忽略
    _updatingLikes[storyId] = true;
  
    try {
      final ref = FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('stories')
          .doc(storyId);
  
      await ref.update({'likes': likes});
    } catch (e) {
      // 🔹 更新失敗，可選擇回滾 UI
      final index = allStories.indexWhere((s) => s['storyId'] == storyId);
      if (index != -1) {
        setState(() {
          // 重新抓 firebase 的資料，保證正確
          allStories[index]['likes'] = List.from(likes); 
        });
      }
    } finally {
      _updatingLikes[storyId] = false;
    }
  }

  void _showComments(String storyOwnerId, String storyId) {
  final commentController = TextEditingController();

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent, // 外框透明
    builder: (context) {
      return SingleChildScrollView(
      // 填充底部間距（鍵盤高度）
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child:Container(
        height: MediaQuery.of(context).size.height * (633 / 917), // 按比例縮放
        width: MediaQuery.of(context).size.width * (412 / 412),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(45),
            topRight: Radius.circular(45),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // --- 標題區 ---
            Container(
              margin: const EdgeInsets.only(top: 15, left: 30),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: const Text(
                "留言",
                style: TextStyle(
                  fontFamily: "Kiwi Maru",
                  fontSize: 20,
                  fontWeight: FontWeight.w500,
                  color: Color.fromRGBO(246, 157, 158, 1),
                ),
              ),
            ),

            const SizedBox(height: 10),

            // --- 留言清單 ---
            Expanded(
              child: Container(
                margin: const EdgeInsets.only(top: 0, left: 13),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(storyOwnerId)
                      .collection('stories')
                      .doc(storyId)
                      .collection('comment')
                      .orderBy('timestamp', descending: true)
                      .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const SizedBox();
                    }
                    final comments = snapshot.data!.docs;

                    return ListView(
                      children: comments.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final commentUserId = data['userId'] as String;
                        final text = data['text'] ?? '';
                        final timestamp = (data['timestamp'] as Timestamp?)?.toDate();

                        return FutureBuilder<DocumentSnapshot>(
                          future: FirebaseFirestore.instance
                              .collection('users')
                              .doc(commentUserId)
                              .get(),
                          builder: (context, userSnap) {
                            if (!userSnap.hasData) {
                              return const SizedBox();
                            }
                            final userData = userSnap.data!.data() as Map<String, dynamic>;
                            final name = userData['name'] ?? '未知用戶';
                            final photoUrl = userData['photoUrl'];

                            return ListTile(
                              leading: Container(
                                width: 48,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color.fromRGBO(255, 200, 202, 1),
                                    width: 3,
                                  ),
                                  image: DecorationImage(
                                    image: photoUrl != null
                                        ? NetworkImage(photoUrl)
                                        : const AssetImage('assets/match_default.jpg') as ImageProvider,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                              title: Text(
                                name,
                                style: const TextStyle(
                                  fontFamily: 'Kiwi Maru',
                                  fontWeight: FontWeight.w500,
                                  fontSize: 14,
                                  height: 1.0,
                                  letterSpacing: 0,
                                  color: Colors.black,
                                ),
                              ),
                              subtitle: Text(
                                text,
                                style: const TextStyle(
                                  fontFamily: 'Inter',
                                  fontWeight: FontWeight.w400,
                                  fontSize: 14,
                                  height: 1.4,
                                  color: Color.fromRGBO(0, 0, 0, 0.5),
                                ),
                              ),
                              trailing: timestamp != null
                                  ? Text(
                                      timeago.format(timestamp),
                                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                                    )
                                  : null,
                            );
                          },
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
            ),

            // --- 固定在底部的輸入留言框 ---
            Container(
              height: 109,
              width: double.infinity,
              color: const Color.fromRGBO(211, 248, 243, 0.99),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance
                        .collection('users')
                        .doc(currentUser.uid)
                        .get(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const CircleAvatar(
                          radius: 24,
                          backgroundColor: Colors.grey,
                        );
                      }
                      final userData = snapshot.data!.data() as Map<String, dynamic>;
                      final photoUrl = userData['photoUrl'];

                      return Container(
                        width: 48,
                        height: 48,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFFFC8CA), width: 3),
                          borderRadius: BorderRadius.circular(24),
                          image: photoUrl != null
                              ? DecorationImage(
                                  image: NetworkImage(photoUrl),
                                  fit: BoxFit.cover,
                                )
                              : null,
                          color: Colors.grey[300], // fallback
                        ),
                      );
                    },
                  ),

                  Expanded(
                    child: Container(
                        //width: 268,   // CSS width: 268px
                        height: 49,   // CSS height: 49px
                        decoration: BoxDecoration(
                          color: Color(0xFFF6DBDC),                                           // background: #F6DBDC
                          border: Border.all(color: Colors.black.withOpacity(0.5), width: 2),  // border: 2px solid rgba(0,0,0,0.5)
                          borderRadius: BorderRadius.circular(100),                           // border-radius: 100px
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),     // 內邊距
                        child: Align(
                          alignment: Alignment.centerLeft,      // 文字靠左＋垂直置中
                          child: TextField(
                            controller: commentController,
                            textAlignVertical: TextAlignVertical.center,
                            decoration: const InputDecoration(
                              hintText: '輸入留言...',
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),

                      ),

                  ),
                  Container(
                    width: 57,
                    height: 59,
                    margin: const EdgeInsets.only(left: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFD1F5F1),                             // 背景 #D1F5F1
                      border: Border.all(color: Colors.black.withOpacity(0.5), width: 2),  
                      borderRadius: BorderRadius.all(
                        Radius.elliptical(57 / 2, 59 / 2),                         // 橢圓半徑
                      ),
                    ),
                    child: Center(
                      child:IconButton(
                        icon:  Image.asset(
                          'assets/airplane.png',
                          width: 51,     // 可依需求調整
                          height: 51,
                          fit: BoxFit.contain,
                        ),

                        onPressed: () async {
                          final text = commentController.text.trim();
                          if (text.isEmpty) return;

                          commentController.clear();
                          final commentRef = FirebaseFirestore.instance
                              .collection('users')
                              .doc(storyOwnerId)
                              .collection('stories')
                              .doc(storyId)
                              .collection('comment')
                              .doc();

                          await commentRef.set({
                            'userId': currentUser.uid,
                            'text': text,
                            'timestamp': FieldValue.serverTimestamp(),
                          });
                        },
                      ),
                    )
                  ),
                  
                ],
              ),
            ),
          ],
        ),
      ),
      );
    },
  );
}


  void _deleteStory(String storyId) async {
    await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .collection('stories')
        .doc(storyId)
        .delete();
    _loadStories();
  }


    // 新增標題區塊widget
  Widget buildTitleBlock(double screenWidth, double screenHeight) {
    double pxW(double px) => screenWidth * (px / 412);
    //double pxH(double px) => screenHeight * (px / 917);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          flex: 1,
          child: Image(
            image: AssetImage('assets/paw.png'),
            width: pxW(28),
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(
          flex: 6,
          child: Text(
            "動態",
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          flex: 1,
          child: IconButton(
            padding: EdgeInsets.zero, // 移除預設內距
            iconSize: pxW(28), // 確保圖片大小一致
            icon: Image.asset('assets/star.png'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => NotificationPage(currentUserId: currentUser.uid),
                ),
              );
            },
          ),
        ),
        Expanded(
          flex: 1,
          child: IconButton(
            icon:  Icon(Icons.add_box_outlined, color: Colors.black, size: pxW(28)),
            onPressed: () {
              _openAddStoryDialog();
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    return Scaffold(
      backgroundColor: Color(0xFCD3F8F3),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(12, 48, 12, 12),
        child: Column(
          children: [
            // 頂部標題區（第二組UI風格）
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              decoration: BoxDecoration(
                color: Color(0xFFFFC8CA),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: buildTitleBlock(screenWidth, screenHeight),
            ),

            const SizedBox(height: 12),
            // 動態列表 
            Expanded(
              child: hasStories
                  ? ListView.builder(
                      key: const PageStorageKey('storyList'), // 🔹 保持 scroll state
                      controller: _scrollController, //**
                      cacheExtent: 10, // 🔹 預先快取上下 10 個 item
                      physics: const AlwaysScrollableScrollPhysics(), // ✅ 確保垂直滾動
                      itemCount: allStories.length,
                      itemBuilder: (context, index) =>
                        StoryCard(
                           story: allStories[index], // 你的 Map<String, dynamic>
                           currentUserId: currentUser.uid,
                           userInfoCache: userInfoCache, // 🔹 傳入緩存使用者資料
                           onEdit: ({String? storyId, Map<String, dynamic>? existingData}) {
                             _openAddStoryDialog(storyId: storyId, existingData: existingData);
                           },
                           onDelete: (String storyId) {
                             _deleteStory(storyId);
                           },
                           onToggleLike: (String userId, String storyId, List<String> likes) {
                             _toggleLike(userId, storyId, likes);
                           },
                           onShowComments: (String userId, String storyId) {
                             _showComments(userId, storyId);
                           },
                         )

                    )
                  
                  : const Center(
                      child: Text(
                        "目前沒有其他人的動態",
                        style: TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                    ),
            ),
            
            
          ],
        ),
      )

    );
    }

  
}





class StoryCard extends StatefulWidget {
  final Map<String, dynamic> story;
  final String currentUserId;
  final Map<String, Map<String, dynamic>> userInfoCache; // 🔹 新增
  // 把原本父層的方法當成 callback 傳進來
  final void Function({String? storyId, Map<String, dynamic>? existingData}) onEdit;
  final void Function(String storyId) onDelete;
  final void Function(String userId, String storyId, List<String> likes) onToggleLike;
  final void Function(String userId, String storyId) onShowComments;

  const StoryCard({
    Key? key,
    required this.story,
    required this.currentUserId,
    required this.userInfoCache,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleLike,
    required this.onShowComments,
  }) : super(key: key);

  @override
  State<StoryCard> createState() => _StoryCardState();
}

class _StoryCardState extends State<StoryCard> {
  bool _isExpanded = false;       // ← 只用一個 bool 狀態就好
  int _currentPage = 0;
  late final PageController _pageController;

    // ✅ 抽出文字樣式，讓量測與 Text 使用同一套 Style
  final TextStyle _contentTextStyle = const TextStyle(
    fontFamily: 'Inter',
    fontWeight: FontWeight.w400,
    fontSize: 14,
    height: 1.4,
    color: Colors.black,
  );

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  bool _isTextOverflowing({
    required String text,
    required TextStyle style,
    required double maxWidth,
    required int maxLines,
    required TextDirection textDirection,
  }) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: maxLines,
      textDirection: textDirection,
    )..layout(maxWidth: maxWidth);
    return tp.didExceedMaxLines;
  }

  @override
  Widget build(BuildContext context) {
    final story = widget.story;
    final userId = story['userId'] as String;
    final storyId = story['storyId'] as String;
    final text = story['text'] ?? '';
    final photoUrls = List<String>.from(story['photoUrls'] ?? []);
    final timestamp = (story['timestamp'] as Timestamp?)?.toDate();
    final likes = List<String>.from(story['likes'] ?? []);

    final screenWidth = MediaQuery.of(context).size.width;
    final imageWidth = screenWidth * (370 / 412);
    final imageHeight = imageWidth * (358 / 370); // 用你的原始比例換算高度

    // 🔹 使用緩存資料取代 FutureBuilder
    final userData = widget.userInfoCache[userId] ?? {};
    final name = userData['name'] ?? '使用者';
    final photoUrl = userData['photoUrl'];
    
    return Container(
      width: screenWidth * (387 / 412),
      margin: const EdgeInsets.only(bottom: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black, width: 2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 頭像 + 名稱 + 時間 + 更多按鈕（保持原本）
            Row(
              children: [
                // ...（你的原本頭像 + 名稱 + PopupMenuButton 代碼）
                Container(
                  width: screenWidth * (34 / 412),
                  height: screenWidth * (34 / 412),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color.fromRGBO(255, 200, 202, 1),
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        offset: const Offset(3, 4),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    backgroundImage: (photoUrl != null && photoUrl.isNotEmpty)
                        ? NetworkImage(photoUrl)
                        : null,
                    child: (photoUrl == null || photoUrl.isEmpty)
                        ? const Icon(Icons.person, size: 18)
                        : null,
                  ),
                ),
                SizedBox(width: screenWidth * (10 / 412)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontFamily: 'Kiwi Maru',
                        fontWeight: FontWeight.w500,
                        fontSize: 15,
                        height: 1.0,
                        color: Colors.black,
                      ),
                    ),
                    if (timestamp != null)
                      Text(
                        timeago.format(timestamp),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color.fromRGBO(130, 130, 130, 1),
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                // 合併為單一三個點選單，依照是否為自己貼文加入編輯/刪除
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) async {
                    if (value == 'report') {
                      try {
                        await FirebaseFirestore.instance.collection('reports').add({
                          'reporterId': FirebaseAuth.instance.currentUser!.uid,
                          'reportedUserId': userId,
                          'storyId': storyId,
                          'storyPath': 'users/$userId/stories/$storyId',
                          'storySnapshot': {
                            'text': text,
                            'photoUrls': photoUrls,
                            'timestamp': story['timestamp'],
                          },
                          'reason': 'user_reported_from_ui',
                          'details': '', // 可讓 user 輸入詳細原因
                          'status': 'pending',
                          'createdAt': FieldValue.serverTimestamp(),
                        });
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已送出檢舉，我們將進行審查。')),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('檢舉失敗：$e')),
                          );
                        }
                      }
                    } else if (value == 'edit') {
                      widget.onEdit(storyId: storyId, existingData: story);
                    } else if (value == 'delete') {
                      widget.onDelete(storyId);
                    }
                  },
                  itemBuilder: (context) {
                    final List<PopupMenuEntry<String>> items = [
                      const PopupMenuItem(value: 'report', child: Text('檢舉')),
                    ];
                    if (userId == widget.currentUserId) {
                      items.add(const PopupMenuDivider());
                      items.addAll(const [
                        PopupMenuItem(value: 'edit', child: Text('編輯')),
                        PopupMenuItem(value: 'delete', child: Text('刪除')),
                      ]);
                    }
                    return items;
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 圖片區（多圖可滑動）
            if (photoUrls.isNotEmpty)
              Center(
                child: SizedBox(
                  width: imageWidth,
                  height: imageHeight,
                  child: Stack(
                    children: [
                      // 🔹 使用 PageView.builder + keepAlive 避免每次重建
                      PageView.builder(
                        controller: _pageController,
                        itemCount: photoUrls.length,
                        onPageChanged: (index) {
                          setState(() => _currentPage = index);
                        },
                        itemBuilder: (context, index) {
                          return _StoryImage(
                            url: photoUrls[index],
                            width: imageWidth,
                            height: imageHeight,
                          );
                        },
                      ),
                      // 圖片頁數指示器
                      Positioned(
                        top: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            "${_currentPage + 1}/${photoUrls.length}",
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ),
                      // 頁數圓點
                      Positioned(
                        bottom: 8,
                        left: 0,
                        right: 0,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: List.generate(photoUrls.length, (index) {
                            final active = _currentPage == index;
                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              width: active ? 8 : 6,
                              height: active ? 8 : 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: active
                                    ? Colors.white
                                    : Colors.white.withOpacity(0.5),
                              ),
                            );
                          }),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              // 無圖顯示預設圖片
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: Image.asset(
                    'assets/qing.png',
                    width: imageWidth,
                    height: imageHeight,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            // 文字內容（保持原本可展開/收起邏輯）
            if (text.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isOverflow = _isTextOverflowing(
                      text: text,
                      style: _contentTextStyle,
                      maxWidth: constraints.maxWidth,
                      maxLines: 2,
                      textDirection: Directionality.of(context),
                    );
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          text,
                          style: _contentTextStyle,
                          maxLines: _isExpanded ? null : 2,
                          overflow: _isExpanded ? TextOverflow.visible : TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        if (!_isExpanded && isOverflow)
                          GestureDetector(
                            onTap: () => setState(() => _isExpanded = true),
                            child: const Text("顯示更多",
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w400,
                                fontSize: 14,
                                height: 1.4,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        if (_isExpanded)
                          GestureDetector(
                            onTap: () => setState(() => _isExpanded = false),
                            child: const Text("收起",
                              style: TextStyle(
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w400,
                                fontSize: 14,
                                height: 1.4,
                                color: Colors.black,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            const SizedBox(height: 12),
            // 按讚與留言（保持原本 StreamBuilder 讀留言）
            Row(
              children: [
                IconButton(
                  icon: Icon(
                    likes.contains(widget.currentUserId)
                        ? Icons.favorite
                        : Icons.favorite_border,
                    color: Colors.red,
                  ),
                  onPressed: () => widget.onToggleLike(userId, storyId, likes),
                ),
                Text('${likes.length}'),
                const SizedBox(width: 12),
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(userId)
                      .collection('stories')
                      .doc(storyId)
                      .collection('comment')
                      .snapshots(),
                  builder: (context, commentCountSnap) {
                    final count = commentCountSnap.hasData
                        ? commentCountSnap.data!.docs.length
                        : 0;
                    return Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.comment),
                          onPressed: () => widget.onShowComments(userId, storyId),
                        ),
                        Text('$count'),
                      ],
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );

  }
}

class _StoryImage extends StatefulWidget {
  final String url;
  final double width;
  final double height;
  const _StoryImage({required this.url, required this.width, required this.height});

  @override
  State<_StoryImage> createState() => _StoryImageState();
}

class _StoryImageState extends State<_StoryImage> with AutomaticKeepAliveClientMixin {
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: CachedNetworkImage(
        imageUrl: widget.url,
        width: widget.width,
        height: widget.height,
        fit: BoxFit.contain,
        placeholder: (context, url) => Center(child: CircularProgressIndicator()),
        errorWidget: (context, url, error) => Icon(Icons.error),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;
}


class NotificationPage extends StatelessWidget {
  final String currentUserId;

  const NotificationPage({Key? key, required this.currentUserId}) : super(key: key);

  Widget userPhotoAvatar(String? fromUserId) {
    if (fromUserId == null || fromUserId.isEmpty) {
      // If no user ID, return default icon
      return CircleAvatar(
        radius: 26,
        backgroundColor: Colors.grey.shade300,
        child: const Icon(Icons.notifications, color: Colors.white),
      );
    }

    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance.collection('users').doc(fromUserId).get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Loading state
          return CircleAvatar(
            radius: 26,
            backgroundColor: Colors.grey.shade300,
            child: CircularProgressIndicator(color: Colors.white),
          );
        }

        if (!snapshot.hasData || !snapshot.data!.exists) {
          // User document not found
          return CircleAvatar(
            radius: 26,
            backgroundColor: Colors.grey.shade300,
            child: const Icon(Icons.notifications, color: Colors.white),
          );
        }

        String? photoUrl = snapshot.data!.get('photoUrl') as String?;
        if (photoUrl == null || photoUrl.isEmpty) {
          // No photo URL available
          return CircleAvatar(
            radius: 26,
            backgroundColor: Colors.grey.shade300,
            child: const Icon(Icons.notifications, color: Colors.white),
          );
        }

        // Display user photo from URL
        return CircleAvatar(
          radius: 26,
          backgroundImage: NetworkImage(photoUrl),
          backgroundColor: Colors.grey.shade300,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    double pxW(double px) => screenWidth * (px / 412);

    return Scaffold(
      backgroundColor: Color(0xFCD3F8F3),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(12, 48, 12, 12),
        child: Column(
          children: [
            // 頂部標題區（第二組UI風格）
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              decoration: BoxDecoration(
                color: Color(0xFFFFC8CA),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.black, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    flex: 1,
                    child: Image(
                      image: AssetImage('assets/paw.png'),
                      width: pxW(22),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    flex: 6,
                    child: Text(
                      "通知",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),                  
                ],
              ),
            ),

            const SizedBox(height: 12),
            // 通知列表 
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.black, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(currentUserId)
                        .collection('notices')
                        .orderBy('timestamp', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
            
                      final notices = snapshot.data!.docs;
            
                      if (notices.isEmpty) {
                        return const Center(
                          child: Text(
                            "目前沒有通知",
                            style: TextStyle(fontSize: 16, color: Colors.grey),
                          ),
                        );
                      }
            
                      return ListView.builder(
                        padding: EdgeInsets.zero,
                        itemCount: notices.length,
                        itemBuilder: (context, index) {
                          final notice = notices[index].data() as Map<String, dynamic>;
                          final fromuserId = notice['fromUserId'] as String?;
                          final title = notice['title'] ?? '無標題';
                          final body = notice['body'] ?? '無內容';
                          final timestamp = (notice['timestamp'] as Timestamp?)?.toDate();
                          final timeStr = timestamp != null
                              ? timeago.format(timestamp)
                              : '';
            
                          return Container(
                            color: Colors.white,
                            child: ListTile(
                              leading: userPhotoAvatar(fromuserId),
                              title: Text(
                                title,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                body,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade700,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: Text(
                                timeStr,
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
            
            
            
          ],
        ),
      )

    );
    }

}