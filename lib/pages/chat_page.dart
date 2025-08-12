import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:image_editor_plus/image_editor_plus.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'dart:typed_data';

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
      // appBar: AppBar(
      //   backgroundColor: Color(0xFFFFC8C8), // 粉色
      //   elevation: 0,
      //   title: Row(
      //     children: [
      //       Icon(Icons.pets, color: Colors.black),
      //       SizedBox(width: 8),
      //       Text("聊天", style: TextStyle(color: Colors.black)),
      //     ],
      //   ),
      //   actions: [
      //     IconButton(icon: Icon(Icons.more_vert, color: Colors.black), onPressed: () {}),
      //   ],
      // ),
      backgroundColor: Color(0xFCD3F8F3), // 淺粉色背景
      body: Padding(
        padding: const EdgeInsets.fromLTRB(12, 48, 12, 12),
        child: Column(
          children: [
            // 頂部標題區
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
                  // 寫固定的
                  // const Image(
                  //   image: AssetImage('assets/paw.png'),
                  //   width: 40,
                  // ),
                  // const Text(
                  //   "聊天",
                  //   style: TextStyle(
                  //     fontSize: 24,
                  //     fontWeight: FontWeight.bold,
                  //   ),
                  // ),
                  // IconButton(
                  //   icon: const Icon(Icons.more_vert, color: Colors.black),
                  //   onPressed: () {
                  //     // 搜尋功能
                  //   },
                  // ),
                  
                  // 寫比例的
                  const Expanded(
                    flex: 1,
                    child: const Image(
                      image: AssetImage('assets/paw.png'),
                      width: 22,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    flex: 6,
                    child: const Text(
                      "聊天",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: IconButton(
                      icon: const Icon(Icons.more_vert, color: Colors.black),
                      onPressed: () {
                        // 搜尋功能
                      },
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // 聊天室列表
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
                    )
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: _buildChats(), // 你原本的聊天列表
                ),
              ),
            ),
          ],
        ),
      ),
      // RefreshIndicator(
      //   onRefresh: () async {
      //     setState(() {}); // 重新觸發 StreamBuilder
      //   },
      //   child: _buildChats(),
      // ),
    );
  }

  Widget _buildChats() {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .where('members', arrayContains: uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('目前沒有聊天室'));
        }

        final chats = snapshot.data!.docs;

        // 按照最後訊息時間排序
        chats.sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aTime = aData['lastMessageTime'] as Timestamp?;
          final bTime = bData['lastMessageTime'] as Timestamp?;
          return (bTime?.toDate() ?? DateTime(0)).compareTo(aTime?.toDate() ?? DateTime(0));
        });

        return ListView.builder(
          padding: EdgeInsets.zero,
          itemCount: chats.length,
          itemBuilder: (context, index) {
            final chat = chats[index];
            final chatData = chat.data() as Map<String, dynamic>;
            final type = chatData['type'] ?? '';
            final lastMessage = chatData['lastMessage'] ?? '';
            final lastMessageTime = chatData['lastMessageTime'] as Timestamp?;
            final timeStr = lastMessageTime != null
                ? DateFormat('MM/dd HH:mm').format(lastMessageTime.toDate())
                : '';
            final displayPhotos = chatData['displayPhotos'] as Map<String, dynamic>? ?? {};
            final myPhotoUrl = displayPhotos[FirebaseAuth.instance.currentUser!.uid] ?? '';
            final cleanLastMessage = lastMessage.replaceAll(RegExp(r'\s+'), ' ');

            String? groupName = '未命名聊天室';
            if (type == 'match') {
              groupName = chatData['displayNames'][FirebaseAuth.instance.currentUser!.uid];
            }
            if (type == 'activity') {
              groupName = chatData['groupName'] ?? '未命名群組';
            }

            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
              ),
              child: ListTile(
                // contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatRoomPage(
                        chatRoomId: chat.id,
                        title: groupName ?? '',
                        avatarUrl: chatData['displayPhotos'][FirebaseAuth.instance.currentUser!.uid] ?? '',
                      ),
                    ),
                  );
                },
                leading: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: Colors.grey.shade300,
                      backgroundImage: (myPhotoUrl.isNotEmpty)
                          ? NetworkImage(myPhotoUrl)
                          : null,
                      child: (myPhotoUrl.isEmpty)
                          ? const Icon(Icons.person, color: Colors.white) // 如果 asset 載不到，至少會顯示這個 icon
                          : null,
                    ),
                    if ((chatData['hasUnread'] as Map<String, dynamic>?)?[FirebaseAuth.instance.currentUser!.uid] == true)
                      Positioned(
                        left: -2,
                        top: 0,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                        ),
                      ),
                  ],
                ),
                title: Text(
                  groupName ?? '未命名聊天室',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  cleanLastMessage,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade700,
                  ),
                  maxLines: 1,  // 限制一行
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
    );
  }

  // Widget _buildMatchChats() {
  //   return StreamBuilder<QuerySnapshot>(
  //     stream: FirebaseFirestore.instance
  //         .collection('users')
  //         .doc(currentUser!.uid)
  //         .collection('matches')
  //         .orderBy('matchedAt', descending: true) // 可選：依照時間排序
  //         .snapshots(),
  //     builder: (context, snapshot) {
  //       if (!snapshot.hasData) {
  //         return const Center(child: CircularProgressIndicator());
  //       }
  
  //       final matchDocs = snapshot.data!.docs;
  
  //       if (matchDocs.isEmpty) {
  //         return const Center(child: Text('目前沒有配對對象'));
  //       }
  
  //       return ListView.builder(
  //         itemCount: matchDocs.length,
  //         itemBuilder: (context, index) {
  //           final matchDoc = matchDocs[index];
  //           final matchedUserId = matchDoc.id; // 文件 ID 就是對方 UID
  
  //           return FutureBuilder<DocumentSnapshot>(
  //             future: FirebaseFirestore.instance.collection('users').doc(matchedUserId).get(),
  //             builder: (context, userSnapshot) {
  //               if (!userSnapshot.hasData) {
  //                 return const ListTile(title: Text('載入中...'));
  //               }
  
  //               final userData = userSnapshot.data!.data() as Map<String, dynamic>? ?? {};
  
  //               return ListTile(
  //                 leading: CircleAvatar(
  //                   backgroundImage: userData['photoURL'] != null
  //                       ? NetworkImage(userData['photoURL'])
  //                       : null,
  //                   child: userData['photoURL'] == null ? const Icon(Icons.person) : null,
  //                 ),
  //                 title: Text(userData['name'] ?? '未知使用者'),
  //                 subtitle: Text(userData['school'] ?? ''),
  //                 onTap: () {
  //                   Navigator.push(
  //                     context,
  //                     MaterialPageRoute(
  //                       builder: (context) => ChatRoomPage(
  //                         chatRoomId: _getMatchRoomId(currentUser!.uid, matchedUserId),
  //                         title: userData['name'] ?? '',
  //                       ),
  //                     ),
  //                   );
  //                 },
  //               );
  //             },
  //           );
  //         },
  //       );
  //     },
  //   );
  // }


  // Widget _buildActivityChats() {
  //   return StreamBuilder<QuerySnapshot>(
  //     stream: FirebaseFirestore.instance
  //         .collection('groupChats')
  //         .where('members', arrayContains: currentUser!.uid)
  //         .snapshots(),
  //     builder: (context, snapshot) {
  //       final docs = snapshot.data?.docs ?? [];

  //       if (docs.isEmpty) {
  //         return const Center(child: Text('目前沒有活動群組'));
  //       }

  //       return ListView.builder(
  //         itemCount: docs.length,
  //         itemBuilder: (context, index) {
  //           final group = docs[index].data() as Map<String, dynamic>;
  //           return ListTile(
  //             leading: const Icon(Icons.group),
  //             title: Text(group['title'] ?? '活動群組'),
  //             subtitle: Text('成員數量：${(group['members'] as List).length}'),
  //             onTap: () {
  //               Navigator.push(
  //                 context,
  //                 MaterialPageRoute(
  //                   builder: (context) => ChatRoomPage(
  //                     chatRoomId: docs[index].id,
  //                     title: group['title'] ?? '活動群組',
  //                   ),
  //                 ),
  //               );
  //             },
  //           );
  //         },
  //       );
  //     },
  //   );
  // }

  // String _getMatchRoomId(String user1, String user2) {
  //   final ids = [user1, user2]..sort();
  //   return ids.join('_');
  // }
}

class ChatRoomPage extends StatefulWidget {
  final String chatRoomId;
  final String title;
  final String avatarUrl;
  
  const ChatRoomPage({
    super.key,
    required this.chatRoomId,
    required this.title,
    required this.avatarUrl,
  });

  @override
  State<ChatRoomPage> createState() => _ChatRoomPageState();
}

class _ChatRoomPageState extends State<ChatRoomPage> {
  final currentUser = FirebaseAuth.instance.currentUser;
  final TextEditingController messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  void sendMessage() async {
    final text = messageController.text.trim();
    messageController.clear();
    if (text.isEmpty) return;

    await FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatRoomId)
        .collection('messages')
        .add({
      'sender': currentUser!.uid,
      'type': 'text',
      'text': text,
      'timestamp': FieldValue.serverTimestamp(),
    });

    await FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatRoomId)
        .update({
      'lastMessage': text,
      'lastMessageTime': FieldValue.serverTimestamp(),
    });
  }

  Future<void> _pickImage(BuildContext context, String chatRoomId) async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);

      if (pickedFile == null) return; // 使用者取消
      File imageFile = File(pickedFile.path);

      // 進入預覽頁面
      final resultFile = await Navigator.push<File?>(
        context,
        MaterialPageRoute(
          builder: (context) => ImagePreviewPage(
            originalImage: imageFile,
            chatRoomId: chatRoomId,
          ),
        ),
      );

      // 預覽頁面送回來的圖片（可能是編輯後的）
      if (resultFile != null) {
        await _uploadAndSendImage(chatRoomId, resultFile);
      }
    } catch (e) {
      print('選擇圖片出錯: $e');
    }
  }

  Future<void> _uploadAndSendImage(String chatRoomId, File imageFile) async {
    final Uint8List? compressedImage = await FlutterImageCompress.compressWithFile(
      imageFile.path,
      minWidth: 800, // 降低解析度
      minHeight: 800,
      quality: 70,   // 壓縮品質
      format: CompressFormat.jpeg, // 轉成 JPEG 省空間
    );

    if (compressedImage == null) {
      throw Exception('壓縮圖片失敗');
    }

    final storageRef = FirebaseStorage.instance
        .ref()
        .child('chat_images')
        .child('${DateTime.now().millisecondsSinceEpoch}.jpg'); // 改成 jpg

    await storageRef.putData(
      compressedImage,
      SettableMetadata(contentType: 'image/jpeg'),
    );

    final downloadUrl = await storageRef.getDownloadURL();
    final currentUser = FirebaseAuth.instance.currentUser;

    // Firestore 新增訊息
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatRoomId)
        .collection('messages')
        .add({
      'sender': currentUser!.uid,
      'type': 'image',
      'imageUrl': downloadUrl,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // 更新聊天室最後訊息
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(chatRoomId)
        .update({
      'lastMessage': '[圖片]',
      'lastMessageTime': FieldValue.serverTimestamp(),
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFCD3F8F3),
      body: Column(
        children: [
          // 最上面的那一列
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 48, 12, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
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
                    flex: 2,
                    child: IconButton(
                      onPressed: () {
                        Navigator.of(context).pop();
                      },
                      icon: Icon(Icons.arrow_back),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: CircleAvatar(
                      radius: 22,
                      backgroundImage: NetworkImage(widget.avatarUrl),
                      child: widget.avatarUrl.isEmpty
                          ? const Icon(Icons.person, color: Colors.white) // 如果 asset 載不到，至少會顯示這個 icon
                          : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 12,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          "3小時前上線",
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                          ),
                        )
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: IconButton(
                      icon: Icon(Icons.phone, color: Colors.black),
                      onPressed: () {}
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: IconButton(
                      icon: Icon(Icons.more_vert, color: Colors.black),
                      onPressed: () {}
                    ),
                  )
                ],
              ),
            ),
          ),

          // 聊天內容區域
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => FocusScope.of(context).unfocus(),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.black, width: 2),
                    borderRadius: BorderRadius.circular(16),
                    image: const DecorationImage(
                      image: AssetImage('assets/profile_setup_background.png'),
                      fit: BoxFit.cover,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('chats')
                          .doc(widget.chatRoomId)
                          .collection('messages')
                          .orderBy('timestamp')
                          .snapshots(),
                      builder: (context, snapshot) {
                        final messages = snapshot.data?.docs ?? [];

                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (_scrollController.hasClients) {
                            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
                          }
                        });

                        return ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(8),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final msg = messages[index].data() as Map<String, dynamic>;
                            final isMe = msg['sender'] == currentUser!.uid;
                            final type = msg['type'] ?? 'text';

                            // 判斷上一則/下一則是否同一發送者
                            final bool sameAsPrev = index > 0 &&
                                (messages[index - 1].data()
                                    as Map<String, dynamic>)['sender'] == msg['sender'];
                            final bool sameAsNext = index < messages.length - 1 &&
                                (messages[index + 1].data()
                                    as Map<String, dynamic>)['sender'] == msg['sender'];

                            // 頭像顯示條件：對方 & 下一則不是同一人
                            final bool showAvatar = !isMe && !sameAsNext;

                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisAlignment:
                                  isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                              children: [
                                if (!isMe) ...[
                                  if (showAvatar)
                                    SizedBox(
                                      width: 38,
                                      child: Padding(
                                        padding: const EdgeInsets.only(right: 6),
                                        child: CircleAvatar(
                                          radius: 18,
                                          backgroundImage: NetworkImage(
                                            widget.avatarUrl,
                                          ),
                                          backgroundColor: Colors.grey.shade300,
                                        ),
                                      ),
                                    )
                                  else
                                    const SizedBox(width: 38),
                                ],
                                Flexible(
                                  child: Container(
                                    padding: type == 'text'
                                        ? const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8)
                                        : EdgeInsets.zero,
                                    margin: EdgeInsets.only(
                                      top: sameAsPrev ? 0 : 6,
                                      bottom: 1.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: type == 'text'
                                          ? (isMe
                                              ? const Color(0xFF89C9C2)
                                              : const Color(0xFFF6DBDC))
                                          : Colors.transparent,
                                      borderRadius: BorderRadius.only(
                                        topLeft: Radius.circular(
                                            isMe ? 12 : (sameAsPrev ? 4 : 12)),
                                        topRight: Radius.circular(
                                            isMe ? (sameAsPrev ? 4 : 12) : 12),
                                        bottomLeft: Radius.circular(
                                            isMe ? 12 : (sameAsNext ? 4 : 12)),
                                        bottomRight: Radius.circular(
                                            isMe ? (sameAsNext ? 4 : 12) : 12),
                                      ),
                                    ),
                                    child: type == 'text'
                                        ? Text(
                                            msg['text'] ?? '',
                                            style: const TextStyle(fontSize: 14),
                                          )
                                        : GestureDetector(
                                            onTap: () {
                                              showDialog(
                                                context: context,
                                                builder: (_) => Dialog(
                                                  backgroundColor: Colors.transparent,
                                                  insetPadding: const EdgeInsets.all(10),
                                                  child: InteractiveViewer(
                                                    child: Image.network(
                                                      msg['imageUrl'] ?? '',
                                                      fit: BoxFit.contain,
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                            child: ClipRRect(
                                              borderRadius: BorderRadius.circular(12),
                                              child: Image.network(
                                                msg['imageUrl'] ?? '',
                                                width: 180,
                                                height: 180,
                                                fit: BoxFit.cover,
                                              ),
                                            ),
                                          ),
                                  ),
                                ),
                              ],
                            );
                          },
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),

          // 最下面的輸入框之類的東西
          Container(
            color: Color(0xFFFFFFFF),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 36),
              child: Row(
                children: [
                  SizedBox(
                    width: 60,
                    height: 60,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: Color(0xFFFFFFFF),
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: () => _pickImage(context, widget.chatRoomId),
                      child: Image.asset(
                        'assets/photo.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12), // 加 vertical padding
                      decoration: BoxDecoration(
                        color: Color(0xFFF6DBDC),
                        borderRadius: BorderRadius.circular(20), // 用 20 之類比較自然的值
                        border: Border.all(color: Colors.black, width: 2),
                      ),
                      child: TextField(
                        controller: messageController,
                        minLines: 1, // 最少一行
                        maxLines: 5, // 最多五行
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          border: InputBorder.none,
                          hintText: "輸入訊息",
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 50,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        elevation: 0,
                        backgroundColor: Color(0xFFD1F5F1),
                        padding: EdgeInsets.zero,
                        side: BorderSide(color: Colors.black, width: 2),
                      ),
                      onPressed: () => sendMessage(),
                      child: Image.asset(
                        'assets/airplane.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ImagePreviewPage extends StatelessWidget {
  final File originalImage;
  final String chatRoomId;

  const ImagePreviewPage({
    Key? key,
    required this.originalImage,
    required this.chatRoomId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: Image.file(originalImage),
          ),
          Positioned(
            bottom: 40,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // 編輯按鈕
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white70,
                    foregroundColor: Colors.black,
                  ),
                  icon: Icon(Icons.edit),
                  label: Text("編輯"),
                  onPressed: () async {
                    final editedImage = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            ImageEditor(image: originalImage),
                      ),
                    );
                    if (editedImage != null) {
                      Navigator.pop(context, File(editedImage.path));
                    }
                  },
                ),
                // 傳送按鈕
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                  ),
                  icon: Icon(Icons.send),
                  label: Text("傳送"),
                  onPressed: () {
                    Navigator.pop(context, originalImage);
                  },
                ),
              ],
            ),
          ),
          // 關閉按鈕
          Positioned(
            top: 40,
            left: 20,
            child: IconButton(
              icon: Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}
