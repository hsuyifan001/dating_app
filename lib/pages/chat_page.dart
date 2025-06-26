import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final currentUser = FirebaseAuth.instance.currentUser;

  @override
  Widget build(BuildContext context) {
    if (currentUser == null) {
      return const Center(child: Text('尚未登入'));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('聊天')),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('matches')
            .where('user1', isEqualTo: currentUser!.uid)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final matchDocs1 = snapshot.data?.docs ?? [];

          // Query for matches where current user is user2
          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('matches')
                .where('user2', isEqualTo: currentUser!.uid)
                .snapshots(),
            builder: (context, snapshot2) {
              final matchDocs2 = snapshot2.data?.docs ?? [];
              final allMatchDocs = [...matchDocs1, ...matchDocs2];

              if (allMatchDocs.isEmpty) {
                return const Center(child: Text('目前沒有配對對象'));
              }

              return ListView.builder(
                itemCount: allMatchDocs.length,
                itemBuilder: (context, index) {
                  final match = allMatchDocs[index].data() as Map<String, dynamic>;
                  String matchedUserId;
                  if (match['user1'] == currentUser!.uid) {
                    matchedUserId = match['user2'];
                  } else {
                    matchedUserId = match['user1'];
                  }

                  return FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance.collection('users').doc(matchedUserId).get(),
                    builder: (context, userSnapshot) {
                      if (!userSnapshot.hasData) {
                        return const ListTile(title: Text('載入中...'));
                      }

                      final userData = userSnapshot.data!.data() as Map<String, dynamic>? ?? {};

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundImage: userSnapshot.data!.exists && userData['photoURL'] != null
                              ? NetworkImage(userData['photoURL'])
                              : null,
                          child: userData['photoURL'] == null ? const Icon(Icons.person) : null,
                        ),
                        title: Text(userData['name'] ?? '未知使用者'),
                        subtitle: Text(userData['school'] ?? ''),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ChatRoomPage(
                                matchedUserId: matchedUserId,
                                matchedUserName: userData['name'] ?? '',
                              ),
                            ),
                          );
                        },
                      );
                    },
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

class ChatRoomPage extends StatefulWidget {
  final String matchedUserId;
  final String matchedUserName;

  const ChatRoomPage({super.key, required this.matchedUserId, required this.matchedUserName});

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  final currentUser = FirebaseAuth.instance.currentUser;
  final TextEditingController messageController = TextEditingController();

  String getChatRoomId() {
    final ids = [currentUser!.uid, widget.matchedUserId];
    ids.sort();
    return ids.join('_');
  }

  void sendMessage() async {
    final text = messageController.text.trim();
    if (text.isEmpty) return;

    await FirebaseFirestore.instance
        .collection('chats')
        .doc(getChatRoomId())
        .collection('messages')
        .add({
      'sender': currentUser!.uid,
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
    });

    messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final chatRoomId = getChatRoomId();

    return Scaffold(
      appBar: AppBar(title: Text(widget.matchedUserName)),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(chatRoomId)
                  .collection('messages')
                  .orderBy('timestamp')
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final messages = snapshot.data!.docs;

                return ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index].data() as Map<String, dynamic>;
                    final isMe = msg['sender'] == currentUser!.uid;

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: isMe ? Colors.pink.shade100 : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(msg['text'] ?? ''),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: messageController,
                    decoration: const InputDecoration(hintText: '輸入訊息...'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: sendMessage,
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}