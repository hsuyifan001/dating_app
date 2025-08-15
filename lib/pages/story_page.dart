// story_page.dart
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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
  @override
  void initState() {
    super.initState();
    _loadMatchedUsers();
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

  Future<void> _loadStories() async {
    List<Map<String, dynamic>> tempStories = [];

    for (var uid in matchedUserIds) {
      final storySnapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('stories')
          .get();

      for (var doc in storySnapshot.docs) {
        final data = doc.data();
        data['storyId'] = doc.id;
        data['userId'] = uid;
        tempStories.add(data);
      }
    }

    // 依照 timestamp 排序（最新在前）
    tempStories.sort((a, b) {
      final tsA = (a['timestamp'] as Timestamp?)?.toDate() ?? DateTime(2000);
      final tsB = (b['timestamp'] as Timestamp?)?.toDate() ?? DateTime(2000);
      return tsB.compareTo(tsA);
    });

    setState(() {
      allStories = tempStories;
      hasStories = tempStories.isNotEmpty; // 新增判斷
    });
  }


  void _openAddStoryDialog({String? storyId, Map<String, dynamic>? existingData}) async {
    final textController = TextEditingController(text: existingData?['text'] ?? '');
    final ImagePicker picker = ImagePicker();
    List<XFile> images = [];

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(storyId == null ? '新增動態' : '編輯動態'),
        content: StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: Column(
              children: [
                TextField(
                  controller: textController,
                  decoration: const InputDecoration(hintText: '說點什麼吧'),
                  maxLines: 3,
                ),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: () async {
                    final picked = await picker.pickMultiImage();
                    if (picked.isNotEmpty) {
                      setState(() => images = picked);
                    }
                  },
                  child: const Text('選擇圖片'),
                ),
                if (images.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    children: images
                        .map((img) => Image.file(File(img.path), width: 80, height: 80))
                        .toList(),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              List<String> uploadedUrls = [];

              for (var img in images) {
                // 1️⃣ 壓縮圖片
                final Uint8List? compressedImage = await FlutterImageCompress.compressWithFile(
                  img.path,
                  minWidth: 800,  // 解析度限制
                  minHeight: 800,
                  quality: 70,    // 壓縮品質
                  format: CompressFormat.jpeg,
                );
              
                if (compressedImage == null) {
                  throw Exception('壓縮圖片失敗');
                }
              
                // 2️⃣ 上傳壓縮後的圖片
                final ref = FirebaseStorage.instance.ref(
                  'story_images/${currentUser.uid}/${DateTime.now().millisecondsSinceEpoch}.jpg',
                );
              
                await ref.putData(
                  compressedImage,
                  SettableMetadata(contentType: 'image/jpeg'),
                );
              
                // 3️⃣ 取得下載 URL
                uploadedUrls.add(await ref.getDownloadURL());
              }

              final storyData = {
                'text': textController.text.trim(),
                'photoUrls': uploadedUrls.isNotEmpty ? uploadedUrls : (existingData?['photoUrls'] ?? []),
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
      ),
    );
  }

  void _toggleLike(String userId, String storyId, List likes) async {
    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('stories')
        .doc(storyId);

    final hasLiked = likes.contains(currentUser.uid);
    if (hasLiked) {
      likes.remove(currentUser.uid);
    } else {
      likes.add(currentUser.uid);
    }
    await ref.update({'likes': likes});
    _loadStories();
  }

  void _addComment(String storyOwnerId, String storyId) async {
    final commentController = TextEditingController();
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('新增留言'),
        content: TextField(
          controller: commentController,
          decoration: const InputDecoration(hintText: '輸入留言'),
          maxLines: 3,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              final text = commentController.text.trim();
              if (text.isEmpty) {
                Navigator.pop(context);
                return;
              }
              Navigator.pop(context);

              final commentRef = FirebaseFirestore.instance
                  .collection('users')
                  .doc(storyOwnerId)
                  .collection('stories')
                  .doc(storyId)
                  .collection('comment') // 使用子集合 'comment'
                  .doc(); // auto id

              await commentRef.set({
                'userId': currentUser.uid,
                'text': text,
                'timestamp': FieldValue.serverTimestamp(),
              });

              // 留言是透過 StreamBuilder 顯示，所以不需要呼叫 _loadStories()
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('留言已送出')));
            },
            child: const Text('送出'),
          ),
        ],
      ),
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

Widget _buildStoryCard(Map<String, dynamic> story) {
  final userId = story['userId'] as String;
  final storyId = story['storyId'] as String;
  final text = story['text'] ?? '';
  final photoUrls = List<String>.from(story['photoUrls'] ?? []);
  final timestamp = (story['timestamp'] as Timestamp?)?.toDate();
  final likes = List<String>.from(story['likes'] ?? []);

  return FutureBuilder<DocumentSnapshot>(
    future: FirebaseFirestore.instance.collection('users').doc(userId).get(),
    builder: (context, snapshot) {
      final userData = snapshot.data?.data() as Map<String, dynamic>? ?? {};
      final name = userData['name'] ?? '使用者';
      final photoUrl = userData['photoUrl'];

      final screenWidth = MediaQuery.of(context).size.width;
      final screenHeight = MediaQuery.of(context).size.height;
      final cardWidth = screenWidth * (387 / 412);
      final cardHeight = screenHeight * (497 / 917);

      PageController pageController = PageController();
      ValueNotifier<int> currentPage = ValueNotifier(0);

      return Container(
        width: cardWidth,
        height: cardHeight,
        margin: const EdgeInsets.only(bottom: 11),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.black, width: 2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 使用者資訊列
              Row(
                children: [
                  Container(
                    width: screenWidth * (34 / 412),
                    height: screenWidth * (34 / 412),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: const Color.fromRGBO(255, 200, 202, 1),
                          width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          offset: const Offset(3, 4),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: CircleAvatar(
                      backgroundImage:
                          photoUrl != null ? NetworkImage(photoUrl) : null,
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
                      SizedBox(height: screenHeight * (2 / 917)),
                      if (timestamp != null)
                        Text(
                          timeago.format(timestamp),
                          style: const TextStyle(
                              fontSize: 12,
                              color: Color.fromRGBO(130, 130, 130, 1)),
                        ),
                    ],
                  ),
                  const Spacer(),
                  if (userId == currentUser.uid)
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_horiz),
                      onSelected: (value) {
                        if (value == 'edit') {
                          _openAddStoryDialog(
                              storyId: storyId, existingData: story);
                        }
                        if (value == 'delete') {
                          _deleteStory(storyId);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('編輯')),
                        PopupMenuItem(value: 'delete', child: Text('刪除')),
                      ],
                    ),
                ],
              ),

              const SizedBox(height: 8),

              // 圖片區（多圖可滑動）
              photoUrls.isNotEmpty
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: screenWidth * (370 / 412),
                      height: screenHeight * (358 / 917),
                      child: Stack(
                        children: [
                          PageView.builder(
                            controller: pageController,
                            itemCount: photoUrls.length,
                            onPageChanged: (index) => currentPage.value = index,
                            itemBuilder: (context, index) {
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.network(
                                  photoUrls[index],
                                  width: screenWidth * (370 / 412),
                                  height: screenHeight * (358 / 917),
                                  fit: BoxFit.cover,
                                ),
                              );
                            },
                          ),
                          // 右上角張數
                          Positioned(
                            top: 8,
                            right: 8,
                            child: ValueListenableBuilder<int>(
                              valueListenable: currentPage,
                              builder: (_, page, __) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    "${page + 1}/${photoUrls.length}",
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 12),
                                  ),
                                );
                              },
                            ),
                          ),
                          // 底部中間點點
                          Positioned(
                            bottom: 8,
                            left: 0,
                            right: 0,
                            child: ValueListenableBuilder<int>(
                              valueListenable: currentPage,
                              builder: (_, page, __) {
                                return Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children:
                                      List.generate(photoUrls.length, (index) {
                                    return Container(
                                      margin:
                                          const EdgeInsets.symmetric(horizontal: 2),
                                      width: page == index ? 8 : 6,
                                      height: page == index ? 8 : 6,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: page == index
                                            ? Colors.white
                                            : Colors.white.withOpacity(0.5),
                                      ),
                                    );
                                  }),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ]
                ):Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.asset(
                      'assets/qing.png', // 你的預設圖片路徑
                      width: screenWidth * (370 / 412),
                      height: screenHeight * (358 / 917),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                

              const SizedBox(height: 12),

              // 文字內容
              if (text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text(
                    text,
                    style: const TextStyle(
                      fontFamily: 'Inter',
                      fontWeight: FontWeight.w400,
                      fontSize: 14,
                      height: 1.4,
                      color: Colors.black,
                    ),
                  ),
                ),

              const Spacer(),

              // 按讚與留言
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      likes.contains(currentUser.uid)
                          ? Icons.favorite
                          : Icons.favorite_border,
                      color: Colors.red,
                    ),
                    onPressed: () => _toggleLike(userId, storyId, likes),
                  ),
                  Text('${likes.length}'),

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
                            onPressed: () => _addComment(userId, storyId),
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
    },
  );
}



  @override
  Widget build(BuildContext context) {
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
                  const Expanded(
                    flex: 1,
                    child: Image(
                      image: AssetImage('assets/paw.png'),
                      width: 22,
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
                      iconSize: 43, // 確保圖片大小一致
                      icon: Image.asset('assets/star.png'),
                      onPressed: () {
                        _openAddStoryDialog();
                      },
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: IconButton(
                      icon: const Icon(Icons.more_vert, color: Colors.black, size: 30),
                      onPressed: () {
                        // TODO: 搜尋或更多功能
                      },
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),
            // 動態列表 
            Expanded(
              child: hasStories
                  ? ListView.builder(
                      itemCount: allStories.length,
                      itemBuilder: (context, index) =>
                          _buildStoryCard(allStories[index]),
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
      /*body: hasStories
        ? ListView.builder(
            itemCount: allStories.length,
            itemBuilder: (context, index) => _buildStoryCard(allStories[index]),
            
          )
        : Center(
            child: Text(
              "目前沒有其他人的動態",
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ),*/
    );
    }

  
}
