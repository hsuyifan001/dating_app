import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

// This page shows a simplified card for each hidden story and only provides
// a restore (unhide) action. The UI displays owner name, first image (if
// any), text preview and timestamp.

class HiddenStoriesPage extends StatefulWidget {
  const HiddenStoriesPage({Key? key}) : super(key: key);

  @override
  State<HiddenStoriesPage> createState() => _HiddenStoriesPageState();
}

class _HiddenStoriesPageState extends State<HiddenStoriesPage> {
  final me = FirebaseAuth.instance.currentUser!.uid;
  final Map<String, Map<String, dynamic>> userInfoCache = {};

  Future<Map<String, dynamic>?> _fetchStory(String ownerId, String storyId) async {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(ownerId)
        .collection('stories')
        .doc(storyId)
        .get();
    if (!doc.exists) return null;
    final raw = doc.data();
    final data = raw is Map<String, dynamic> ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    data['storyId'] = doc.id;
    data['userId'] = ownerId;
    return data;
  }

  Future<void> _ensureUserInfo(String uid) async {
    if (userInfoCache.containsKey(uid)) return;
    final udoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final raw = udoc.data();
    userInfoCache[uid] = raw is Map<String, dynamic> ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final imageWidth = screenWidth * (370 / 412);
    final imageHeight = imageWidth * (358 / 370);
    return Scaffold(
      appBar: AppBar(
        title: const Text('隱藏的動態'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(me)
            .collection('hiddenStories')
            .orderBy('hiddenAt', descending: true)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(child: Text('目前沒有隱藏的動態'));
          }

          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, idx) {
              final doc = docs[idx];
              final storyId = doc.id;
              final ownerId = (doc.data() as Map<String, dynamic>?)?['ownerId'] as String? ?? '';

              // For each hidden entry, fetch the actual story document and render StoryCard
              return FutureBuilder<Map<String, dynamic>?>(
                future: _fetchStory(ownerId, storyId),
                builder: (context, storySnap) {
                  if (storySnap.connectionState == ConnectionState.waiting) {
                    return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator()));
                  }
                  final story = storySnap.data;
                  if (story == null) {
                    // story deleted or missing
                    return ListTile(
                      title: Text('貼文已不存在'),
                      subtitle: Text('貼文 id: $storyId • 來自 $ownerId'),
                      trailing: TextButton(
                        child: const Text('移除紀錄'),
                        onPressed: () async {
                          await FirebaseFirestore.instance
                              .collection('users')
                              .doc(me)
                              .collection('hiddenStories')
                              .doc(storyId)
                              .delete();
                        },
                      ),
                    );
                  }

                  // ensure we have user info cached
                  _ensureUserInfo(ownerId);

                  final userInfo = userInfoCache[ownerId] ?? {};
                  final ownerName = userInfo['name'] as String? ?? ownerId;
                  final ownerPhoto = userInfo['photoUrl'] as String?;
                  final photoUrls = (story['photoUrls'] is List) ? List<String>.from(story['photoUrls']) : <String>[];
                  final text = (story['text'] as String?) ?? '';
                  final timestamp = (story['timestamp'] as Timestamp?)?.toDate();

                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 20,
                                backgroundImage: ownerPhoto != null && ownerPhoto.isNotEmpty ? NetworkImage(ownerPhoto) : null,
                                child: ownerPhoto == null || ownerPhoto.isEmpty ? const Icon(Icons.person) : null,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(ownerName, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    if (timestamp != null) Text('${timestamp.toLocal()}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                  ],
                                ),
                              ),
                              TextButton(
                                onPressed: () async {
                                  // restore (remove hiddenStories entry)
                                  await FirebaseFirestore.instance.collection('users').doc(me).collection('hiddenStories').doc(storyId).delete();
                                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已還原')));
                                },
                                child: const Text('還原'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (photoUrls.isNotEmpty)
                            Center(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  color: Colors.grey[200],
                                  child: SizedBox(
                                    width: imageWidth,
                                    height: imageHeight,
                                    child: CachedNetworkImage(
                                      imageUrl: photoUrls.first,
                                      fit: BoxFit.contain,
                                      alignment: Alignment.center,
                                      width: imageWidth,
                                      height: imageHeight,
                                      placeholder: (context, url) => const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                      errorWidget: (context, url, error) => const Center(child: Icon(Icons.broken_image)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          if (text.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(text),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
