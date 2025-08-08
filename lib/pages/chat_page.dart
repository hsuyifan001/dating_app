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
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text('配對聊天', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          Expanded(child: _buildMatchChats()),

          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text('活動聊天室', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ),
          Expanded(child: _buildActivityChats()),
        ],
      ),
    );
  }

  Widget _buildMatchChats() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser!.uid)
          .collection('matches')
          .orderBy('matchedAt', descending: true) // 可選：依照時間排序
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
  
        final matchDocs = snapshot.data!.docs;
  
        if (matchDocs.isEmpty) {
          return const Center(child: Text('目前沒有配對對象'));
        }
  
        return ListView.builder(
          itemCount: matchDocs.length,
          itemBuilder: (context, index) {
            final matchDoc = matchDocs[index];
            final matchedUserId = matchDoc.id; // 文件 ID 就是對方 UID
  
            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance.collection('users').doc(matchedUserId).get(),
              builder: (context, userSnapshot) {
                if (!userSnapshot.hasData) {
                  return const ListTile(title: Text('載入中...'));
                }
  
                final userData = userSnapshot.data!.data() as Map<String, dynamic>? ?? {};
  
                return ListTile(
                  leading: CircleAvatar(
                    backgroundImage: userData['photoURL'] != null
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
                          chatRoomId: _getMatchRoomId(currentUser!.uid, matchedUserId),
                          title: userData['name'] ?? '',
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
  }


  Widget _buildActivityChats() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('groupChats')
          .where('members', arrayContains: currentUser!.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = snapshot.data?.docs ?? [];

        if (docs.isEmpty) {
          return const Center(child: Text('目前沒有活動群組'));
        }

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final group = docs[index].data() as Map<String, dynamic>;
            return ListTile(
              leading: const Icon(Icons.group),
              title: Text(group['title'] ?? '活動群組'),
              subtitle: Text('成員數量：${(group['members'] as List).length}'),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ChatRoomPage(
                      chatRoomId: docs[index].id,
                      title: group['title'] ?? '活動群組',
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  String _getMatchRoomId(String user1, String user2) {
    final ids = [user1, user2]..sort();
    return ids.join('_');
  }
}

class ChatRoomPage extends StatefulWidget {
  final String chatRoomId;
  final String title;

  const ChatRoomPage({
    super.key,
    required this.chatRoomId,
    required this.title,
  });

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  final currentUser = FirebaseAuth.instance.currentUser;
  final TextEditingController messageController = TextEditingController();

  void sendMessage() async {
    final text = messageController.text.trim();
    if (text.isEmpty) return;

    await FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatRoomId)
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
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('chats')
                  .doc(widget.chatRoomId)
                  .collection('messages')
                  .orderBy('timestamp')
                  .snapshots(),
              builder: (context, snapshot) {
                final messages = snapshot.data?.docs ?? [];

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
