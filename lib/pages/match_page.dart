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

  Future<void> _handleLike(String targetUserId) async {
    final currentUserId = user!.uid;
    final currentUserRef = FirebaseFirestore.instance.collection('users').doc(currentUserId);
    final targetUserRef = FirebaseFirestore.instance.collection('users').doc(targetUserId);

    // 加入 likes 資料
    await FirebaseFirestore.instance
        .collection('likes')
        .doc('$currentUserId\_$targetUserId')
        .set({
      'from': currentUserId,
      'to': targetUserId,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // 檢查對方是否也按過愛心
    final reverseLike = await FirebaseFirestore.instance
        .collection('likes')
        .doc('$targetUserId\_$currentUserId')
        .get();

    if (reverseLike.exists) {
      // 配對成功，儲存到 matches 資料中
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
        );
      }
    }
  }

  Future<void> _handleDislike(String targetUserId) async {
    // 你可以在這裡實作記錄不喜歡的邏輯，例如加入一個 dislikes collection
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: users.length,
      itemBuilder: (context, index) {
        final userData = users[index].data() as Map<String, dynamic>;
        final userId = users[index].id;
        final name = userData['name'] ?? '未知使用者';
        final bio = userData['bio'] ?? '';
        final school = userData['school'] ?? '';
        final tags = List<String>.from(userData['tags'] ?? []);

        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Text(school, style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 8),
                if (bio.isNotEmpty) Text(bio),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: tags
                      .map((tag) => Chip(
                            label: Text(tag),
                            backgroundColor: Colors.pink.shade100,
                          ))
                      .toList(),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.clear, color: Colors.grey),
                      onPressed: () => _handleDislike(userId),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.favorite, color: Colors.pink),
                      onPressed: () => _handleLike(userId),
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
}