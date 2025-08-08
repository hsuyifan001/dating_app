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

  @override
  void initState() {
    super.initState();
    _loadMatchedUsers();
  }

  Future<void> _loadMatchedUsers() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('users')
        .doc(currentUser.uid)
        .collection('matchedUsers')
        .get();

    setState(() {
      matchedUserIds = snapshot.docs.map((doc) => doc.id).toList();
      matchedUserIds.add(currentUser.uid); // 顯示自己動態
    });
  }

  void _openAddStoryDialog({DocumentSnapshot? existingStory}) async {
    final textController = TextEditingController(
        text: existingStory != null ? existingStory['text'] : '');
    final ImagePicker picker = ImagePicker();
    List<XFile> images = [];

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(existingStory == null ? '新增動態' : '編輯動態'),
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
                    runSpacing: 8,
                    children: images
                        .map((img) => Image.file(
                              File(img.path),
                              width: 80,
                              height: 80,
                            ))
                        .toList(),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              List<String> uploadedUrls = [];

              for (var img in images) {
                final ref = FirebaseStorage.instance
                    .ref('story_images/${currentUser.uid}/${DateTime.now().millisecondsSinceEpoch}.jpg');
                await ref.putFile(File(img.path));
                final url = await ref.getDownloadURL();
                uploadedUrls.add(url);
              }

              final storyData = {
                'userId': currentUser.uid,
                'text': textController.text.trim(),
                'photoUrls': uploadedUrls,
                'timestamp': FieldValue.serverTimestamp(),
                'likes': [],
              };

              if (existingStory == null) {
                await FirebaseFirestore.instance.collection('stories').add(storyData);
              } else {
                await existingStory.reference.update(storyData);
              }
            },
            child: const Text('發布'),
          ),
        ],
      ),
    );
  }

  void _openCommentDialog(DocumentSnapshot story) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('留言功能'),
        content: const Text('這裡可以擴充成留言清單與新增留言功能。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('關閉'),
          ),
        ],
      ),
    );
  }

  void _toggleLike(DocumentSnapshot story) async {
    final docRef = story.reference;
    final likes = List<String>.from(story['likes'] ?? []);
    final hasLiked = likes.contains(currentUser.uid);

    if (hasLiked) {
      likes.remove(currentUser.uid);
    } else {
      likes.add(currentUser.uid);
    }

    await docRef.update({'likes': likes});
  }

  void _deleteStory(DocumentSnapshot story) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('確認刪除'),
        content: const Text('你確定要刪除這則動態嗎？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('刪除')),
        ],
      ),
    );

    if (confirm == true) {
      await story.reference.delete();
    }
  }

  Widget _buildStoryCard(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final userId = data['userId'];
    final text = data['text'] ?? '';
    final photoUrls = List<String>.from(data['photoUrls'] ?? []);
    final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
    final likes = List<String>.from(data['likes'] ?? []);

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
                // 使用者資料
                Row(
                  children: [
                    CircleAvatar(
                      backgroundImage:
                          photoUrl != null ? NetworkImage(photoUrl) : null,
                      child: photoUrl == null ? const Icon(Icons.person) : null,
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        if (timestamp != null)
                          Text(
                            timeago.format(timestamp, locale: 'en_short'),
                            style: const TextStyle(color: Colors.grey),
                          ),
                      ],
                    ),
                    const Spacer(),
                    if (userId == currentUser.uid)
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'edit') _openAddStoryDialog(existingStory: doc);
                          if (value == 'delete') _deleteStory(doc);
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'edit', child: Text('編輯')),
                          const PopupMenuItem(value: 'delete', child: Text('刪除')),
                        ],
                      )
                  ],
                ),
                const SizedBox(height: 8),
                // 文字內容
                if (text.isNotEmpty) Text(text),
                const SizedBox(height: 8),
                // 圖片
                if (photoUrls.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: photoUrls
                        .map((url) => Image.network(
                              url,
                              width: 120,
                              height: 120,
                              fit: BoxFit.cover,
                            ))
                        .toList(),
                  ),
                const SizedBox(height: 8),
                // Like & Comment
                Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        likes.contains(currentUser.uid)
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: Colors.red,
                      ),
                      onPressed: () => _toggleLike(doc),
                    ),
                    Text('${likes.length}'),
                    IconButton(
                      icon: const Icon(Icons.comment),
                      onPressed: () => _openCommentDialog(doc),
                    ),
                  ],
                )
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
      body: matchedUserIds.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('stories')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const CircularProgressIndicator();

                final docs = snapshot.data!.docs.where((doc) {
                  final userId = doc['userId'];
                  return matchedUserIds.contains(userId);
                }).toList();

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) =>
                      _buildStoryCard(docs[index]),
                );
              },
            ),
    );
  }
}
