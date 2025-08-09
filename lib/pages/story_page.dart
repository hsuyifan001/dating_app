// story_page.dart
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:timeago/timeago.dart' as timeago;

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
                final ref = FirebaseStorage.instance
                    .ref('story_images/${currentUser.uid}/${DateTime.now().millisecondsSinceEpoch}.jpg');
                await ref.putFile(File(img.path));
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
  
        return Card(
          margin: const EdgeInsets.all(10),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 使用者資訊列
                Row(
                  children: [
                    CircleAvatar(
                      backgroundImage: photoUrl != null ? NetworkImage(photoUrl) : null,
                      child: photoUrl == null ? const Icon(Icons.person) : null,
                    ),
                    const SizedBox(width: 8),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (timestamp != null)
                        Text(timeago.format(timestamp), style: const TextStyle(color: Colors.grey)),
                    ]),
                    const Spacer(),
                    if (userId == currentUser.uid)
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'edit') {
                            _openAddStoryDialog(storyId: storyId, existingData: story);
                          }
                          if (value == 'delete') {
                            _deleteStory(storyId);
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'edit', child: Text('編輯')),
                          const PopupMenuItem(value: 'delete', child: Text('刪除')),
                        ],
                      ),
                  ],
                ),
  
                const SizedBox(height: 8),
  
                // 文字 & 圖片
                if (text.isNotEmpty) Text(text),
                if (photoUrls.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: photoUrls.map((url) {
                      return Image.network(url, width: 120, height: 120, fit: BoxFit.cover);
                    }).toList(),
                  ),
  
                const SizedBox(height: 8),
  
                // 按讚 + 留言按鈕（留言數用 StreamBuilder 即時更新）
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        likes.contains(currentUser.uid) ? Icons.favorite : Icons.favorite_border,
                        color: Colors.red,
                      ),
                      onPressed: () => _toggleLike(userId, storyId, likes),
                    ),
                    Text('${likes.length}'),
  
                    // 留言按鈕與即時數字
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .doc(userId)
                          .collection('stories')
                          .doc(storyId)
                          .collection('comment')
                          .snapshots(),
                      builder: (context, commentCountSnap) {
                        final count = commentCountSnap.hasData ? commentCountSnap.data!.docs.length : 0;
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
  
                const SizedBox(height: 6),
  
                // 留言清單（最新在下方或依 orderBy 設定）
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(userId)
                      .collection('stories')
                      .doc(storyId)
                      .collection('comment')
                      .orderBy('timestamp', descending: false) // 可改 descending: true
                      .snapshots(),
                  builder: (context, commentSnap) {
                    if (!commentSnap.hasData || commentSnap.data!.docs.isEmpty) {
                      // 若沒有留言可回傳空容器（或顯示 '目前還沒有留言'）
                      return const SizedBox(); // 或： return Padding(...Text('目前還沒有留言'));
                    }
  
                    final commentDocs = commentSnap.data!.docs;
  
                    // 使用 Column 顯示留言（小量留言 ok；量大時可改成 ListView shrinkwrap）
                    return Column(
                      children: commentDocs.map((cDoc) {
                        final c = cDoc.data() as Map<String, dynamic>;
                        final cUserId = c['userId'] as String?;
                        final cText = c['text'] ?? '';
                        final cTs = (c['timestamp'] as Timestamp?)?.toDate();
  
                        // 取留言者名字/頭像
                        return FutureBuilder<DocumentSnapshot>(
                          future: FirebaseFirestore.instance.collection('users').doc(cUserId).get(),
                          builder: (context, userSnap) {
                            final cuData = userSnap.data?.data() as Map<String, dynamic>? ?? {};
                            final cuName = cuData['name'] ?? '使用者';
                            final cuPhoto = cuData['photoUrl'];
  
                            return Padding(
                              padding: const EdgeInsets.only(left: 8.0, top: 6.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    radius: 12,
                                    backgroundImage: cuPhoto != null ? NetworkImage(cuPhoto) : null,
                                    child: cuPhoto == null ? const Icon(Icons.person, size: 12) : null,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(cuName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                            const SizedBox(width: 8),
                                            if (cTs != null)
                                              Text(timeago.format(cTs), style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                          ],
                                        ),
                                        const SizedBox(height: 2),
                                        Text(cText),
                                      ],
                                    ),
                                  ),
                                  // 若是自己的留言，顯示刪除按鈕
                                  if (cUserId == currentUser.uid)
                                    IconButton(
                                      icon: const Icon(Icons.delete, size: 18),
                                      onPressed: () async {
                                        await cDoc.reference.delete();
                                      },
                                    ),
                                ],
                              ),
                            );
                          },
                        );
                      }).toList(),
                    );
                  },
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
      appBar: AppBar(
        title: const Text('動態'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _openAddStoryDialog(),
          ),
        ],
      ),
      body: hasStories
        ? ListView.builder(
            itemCount: allStories.length,
            itemBuilder: (context, index) => _buildStoryCard(allStories[index]),
            
          )
        : Center(
            child: Text(
              "目前沒有其他人的動態",
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ),
    );
    }

  
}
