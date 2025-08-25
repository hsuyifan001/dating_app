import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
// import 'package:image_editor_plus/image_editor_plus.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'dart:typed_data';
import 'dart:async';
// import 'package:path_provider/path_provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final uid = FirebaseAuth.instance.currentUser!.uid;
  final List<DocumentSnapshot> _chatDocs = [];
  final int _limit = 20; // 設為20 因debug需要，先設為10
  bool _isLoading = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDoc;
  final ScrollController _scrollController = ScrollController();

  StreamSubscription<QuerySnapshot>? _subscription;

  @override
  void initState() {
    super.initState();
    _listenLatestChats();
    _scrollController.addListener(_scrollListener);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  void _listenLatestChats() {
    final query = FirebaseFirestore.instance
        .collection('chats')
        .where('members', arrayContains: uid)
        .orderBy('lastMessageTime', descending: true)
        .limit(_limit);

    _subscription = query.snapshots().listen((snapshot) {
      final latestDocs = snapshot.docs;

      if (_chatDocs.isEmpty) {
        _chatDocs.addAll(latestDocs);
      } else {
        for (var doc in latestDocs) {
          final index = _chatDocs.indexWhere((c) => c.id == doc.id);
          if (index >= 0) {
            _chatDocs[index] = doc;
          } else {
            _chatDocs.insert(0, doc);
          }
        }
      }

      // 判斷是否還有更多資料
      if (latestDocs.length < _limit) {
        _hasMore = false;  // **這裡很重要**
      } else {
        _hasMore = true;
      }

      _chatDocs.sort((a, b) {
        final aTime = (a.data() as Map<String, dynamic>)['lastMessageTime'] as Timestamp?;
        final bTime = (b.data() as Map<String, dynamic>)['lastMessageTime'] as Timestamp?;
        return (bTime?.toDate() ?? DateTime(0)).compareTo(aTime?.toDate() ?? DateTime(0));
      });

      if (_chatDocs.isNotEmpty) {
        _lastDoc = _chatDocs.last;
      }

      setState(() {});
    });
  }

  void _scrollListener() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoading &&
        _hasMore) {
      _loadMoreChats();
    }
  }

  Future<void> _loadMoreChats() async {
    if (_isLoading || _lastDoc == null) return;
    setState(() => _isLoading = true);

    Query query = FirebaseFirestore.instance
        .collection('chats')
        .where('members', arrayContains: uid)
        .orderBy('lastMessageTime', descending: true)
        .startAfterDocument(_lastDoc!)
        .limit(_limit);

    final snapshot = await query.get();
    if (snapshot.docs.isNotEmpty) {
      _chatDocs.addAll(snapshot.docs);
      _lastDoc = snapshot.docs.last;
    }

    if (snapshot.docs.length < _limit) {
      _hasMore = false;
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_chatDocs.isEmpty) {
      return const Center(child: Text('目前沒有聊天室'));
    }

    return Scaffold(
      backgroundColor: Color(0xFCD3F8F3), // 淺粉色背景
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
                      "聊天",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 1,
                    child: SizedBox(), // 暫時將三個點隱藏起來
                    // child: IconButton(
                    //   icon: const Icon(Icons.more_vert, color: Colors.black),
                    //   onPressed: () {
                    //     // TODO: 搜尋或更多功能
                    //   },
                    // ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // 聊天室列表外層裝飾容器（第二組UI風格）
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
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.zero,
                    itemCount: _chatDocs.length + 1,
                    itemBuilder: (context, index) {
                      if (index == _chatDocs.length) {
                        return _hasMore
                            ? const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Center(child: CircularProgressIndicator()),
                              )
                            : const SizedBox.shrink();
                      }

                      final chat = _chatDocs[index];
                      final chatData = chat.data() as Map<String, dynamic>;

                      final type = chatData['type'] ?? '';
                      final lastMessage = chatData['lastMessage'] ?? '';
                      final lastMessageTime = chatData['lastMessageTime'] as Timestamp?;
                      final timeStr = lastMessageTime != null
                          ? DateFormat('MM/dd HH:mm').format(lastMessageTime.toDate())
                          : '';

                      final cleanLastMessage = lastMessage.replaceAll(RegExp(r'\s+'), ' ');

                      String? groupName = '未命名聊天室';
                      if (type == 'match') {
                        groupName = chatData['displayNames'][uid];
                      }
                      if (type == 'activity') {
                        groupName = chatData['groupName'] ?? '未命名群組';
                      }

                      String myPhotoUrl = '';
                      if (type == 'match') {
                        final displayPhotos = chatData['displayPhotos'] as Map<String, dynamic>? ?? {};
                        myPhotoUrl = displayPhotos[uid] ?? '';
                      }
                      if(type == 'activity') {
                        myPhotoUrl = chatData['groupPhotoUrl'] ?? '';
                      }

                      return Container(
                        color: Colors.white,
                        child: ListTile(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ChatRoomPage(
                                  chatRoomId: chat.id,
                                  title: groupName ?? '',
                                  avatarUrl: myPhotoUrl,
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
                                backgroundImage:
                                    (myPhotoUrl.isNotEmpty) ? NetworkImage(myPhotoUrl) : null,
                                child: (myPhotoUrl.isEmpty)
                                    ? const Icon(Icons.person, color: Colors.white)
                                    : null,
                              ),
                              if ((chatData['hasUnread'] as Map<String, dynamic>?)?[uid] ==
                                  true)
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
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
  Map<String, dynamic> _displayPhotos = {}; // 🆕 新增一個 map 來存頭貼

  List<Map<String, dynamic>> _localTempMessages = [];

  @override
  void initState() {
    super.initState();
    _loadChatInfo();
  }

  Future<void> _loadChatInfo() async {
    final doc = await FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatRoomId)
        .get();
    if (doc.exists) {
      setState(() {
        _displayPhotos = (doc.data()?['displayPhotos'] as Map<String, dynamic>?) ?? {};
      });
    }
  }

  void _addTempImageMessage(File imageFile) {
    setState(() {
      _localTempMessages.add({
        'isTemp': true,
        'type': 'image',
        'localFile': imageFile,
        'progress': 0.0,
        'sender': currentUser!.uid,
        'tempId': DateTime.now().millisecondsSinceEpoch.toString(),
      });
    });
  }

  void _updateTempImageProgress(String tempId, double progress) {
    print('進度更新: tempId=$tempId, progress=$progress'); // 添加日誌
    setState(() {
      for (var msg in _localTempMessages) {
        if (msg['tempId'] == tempId) {
          msg['progress'] = progress;
        }
      }
    });
  }

  void _removeTempImageMessage(String tempId) {
    setState(() {
      _localTempMessages.removeWhere((msg) => msg['tempId'] == tempId);
    });
  }

  void sendMessage() async {
    final text = messageController.text.trim();
    messageController.clear();
    FocusScope.of(context).unfocus();
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
    final tempId = DateTime.now().millisecondsSinceEpoch.toString();
    _addTempImageMessage(imageFile);

    try {
      final Uint8List? compressedImage = await FlutterImageCompress.compressWithFile(
        imageFile.path,
        minWidth: 800,
        minHeight: 800,
        quality: 70,
        format: CompressFormat.jpeg,
      );

      if (compressedImage == null) throw Exception('壓縮圖片失敗');

      final storageRef = FirebaseStorage.instance
          .ref()
          .child('chat_images')
          .child(chatRoomId)
          .child('$tempId.jpg');

      final uploadTask = storageRef.putData(
        compressedImage,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      uploadTask.snapshotEvents.listen((snapshot) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        _updateTempImageProgress(tempId, progress);
      });

      await uploadTask;
      final downloadUrl = await storageRef.getDownloadURL();

      // 提前移除臨時訊息
      _removeTempImageMessage(tempId);

      // 寫入 Firestore
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatRoomId)
          .collection('messages')
          .add({
        'sender': currentUser!.uid,
        'type': 'image',
        'imageUrl': downloadUrl,
        'timestamp': FieldValue.serverTimestamp(),
        'tempId': tempId, // 添加 tempId 至 Firestore 訊息，方便後續過濾
      });

      // 更新聊天室資訊
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatRoomId)
          .update({
        'lastMessage': '[圖片]',
        'lastMessageTime': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('圖片上傳失敗: $e')),
      );
      _removeTempImageMessage(tempId);
    }
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
                    child: SizedBox(
                      width: 44,  // 直徑=radius*2
                      height: 44,
                      child: CircleAvatar(
                        radius: 22, // 等於直徑 44 / 2
                        backgroundImage: widget.avatarUrl.isEmpty
                            ? null
                            : NetworkImage(widget.avatarUrl),
                        child: widget.avatarUrl.isEmpty
                            ? const Icon(Icons.person, color: Colors.white)
                            : null,
                      )
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
                        // Text(
                        //   "3小時前上線",
                        //   style: TextStyle(
                        //     fontSize: 12,
                        //     color: Colors.grey,
                        //   ),
                        // )
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: SizedBox(), // 暫時將電話按鈕隱藏
                    // child: IconButton(
                    //   icon: Icon(Icons.phone, color: Colors.black),
                    //   onPressed: () {}
                    // ),
                  ),
                  Expanded(
                    flex: 2,
                    child: SizedBox(), // 暫時將三個點隱藏起來
                    // child: IconButton(
                    //   icon: Icon(Icons.more_vert, color: Colors.black),
                    //   onPressed: () {}
                    // ),
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
                      image: AssetImage('assets/chat_background.png'),
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
                        if (snapshot.hasError) {
                          return const Center(child: Text('載入訊息失敗'));
                        }
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final messages = snapshot.data?.docs ?? [];
                        final firebaseMessages = messages.map((doc) => doc.data() as Map<String, dynamic>).toList();

                        final allMessages = [
                          ...firebaseMessages.where((msg) {
                            final msgTempId = msg['tempId'];
                            return msgTempId == null || !_localTempMessages.any((tempMsg) => tempMsg['tempId'] == msgTempId);
                          }),
                          ..._localTempMessages,
                        ];

                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (_scrollController.hasClients && allMessages.isNotEmpty) {
                            _scrollController.animateTo(
                              _scrollController.position.maxScrollExtent,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                            );
                          }
                        });

                        return ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(8),
                          itemCount: allMessages.length,
                          itemBuilder: (context, index) {
                            final msg = allMessages[index];
                            final isTemp = msg['isTemp'] == true;
                            final isMe = msg['sender'] == currentUser!.uid;
                            final type = msg['type'] ?? 'text';

                            final bool sameAsPrev = index > 0 &&
                                allMessages[index - 1]['sender'] == msg['sender'];
                            final bool sameAsNext = index < allMessages.length - 1 &&
                                allMessages[index + 1]['sender'] == msg['sender'];

                            final bool showAvatar = !isMe && !sameAsNext;

                            final senderId = msg['sender'] as String;
                            final senderPhoto = _displayPhotos[senderId] ?? '';

                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                              children: [
                                if (!isMe) ...[
                                  if (showAvatar)
                                    SizedBox(
                                      width: 38,
                                      child: Padding(
                                        padding: const EdgeInsets.only(right: 6),
                                        child: CircleAvatar(
                                          radius: 18,
                                          backgroundImage: senderPhoto.isNotEmpty ? NetworkImage(senderPhoto) : null,
                                          backgroundColor: Colors.grey.shade300,
                                          child: senderPhoto.isEmpty
                                              ? const Icon(Icons.person, color: Colors.white, size: 18)
                                              : null,
                                        ),
                                      ),
                                    )
                                  else
                                    const SizedBox(width: 38),
                                ],
                                Flexible(
                                  child: Container(
                                    margin: EdgeInsets.only(
                                      top: sameAsPrev ? 0 : 6,
                                      bottom: 1.5,
                                    ),
                                    child: isTemp
                                        ? Stack(
                                            children: [
                                              ClipRRect(
                                                borderRadius: BorderRadius.only(
                                                  topLeft: Radius.circular(isMe ? 16 : (sameAsPrev ? 4 : 16)),
                                                  topRight: Radius.circular(isMe ? (sameAsPrev ? 4 : 16) : 16),
                                                  bottomLeft: Radius.circular(isMe ? 16 : (sameAsNext ? 4 : 16)),
                                                  bottomRight: Radius.circular(isMe ? (sameAsNext ? 4 : 16) : 16),
                                                ),
                                                child: Image.file(
                                                  msg['localFile'],
                                                  width: 180,
                                                  height: 180,
                                                  fit: BoxFit.cover,
                                                ),
                                              ),
                                              if (msg['progress'] != null && msg['progress'] < 1.0)
                                                Positioned.fill(
                                                  child: ClipRRect(
                                                    borderRadius: BorderRadius.only(
                                                      topLeft: Radius.circular(isMe ? 16 : (sameAsPrev ? 4 : 16)),
                                                      topRight: Radius.circular(isMe ? (sameAsPrev ? 4 : 16) : 16),
                                                      bottomLeft: Radius.circular(isMe ? 16 : (sameAsNext ? 4 : 16)),
                                                      bottomRight: Radius.circular(isMe ? (sameAsNext ? 4 : 16) : 16),
                                                    ),
                                                    child: Container(
                                                      color: Colors.black54,
                                                      child: Center(
                                                        child: CircularProgressIndicator(
                                                          value: msg['progress'],
                                                          strokeWidth: 5,
                                                          color: Colors.blue,
                                                          backgroundColor: Colors.white30,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                            ],
                                          )
                                        : type == 'image'
                                            ? Stack(
                                                children: [
                                                  GestureDetector(
                                                    onTap: () {
                                                      showDialog(
                                                        context: context,
                                                        builder: (_) => Dialog(
                                                          backgroundColor: Colors.transparent,
                                                          insetPadding: const EdgeInsets.all(10),
                                                          child: Stack(
                                                            children: [
                                                              InteractiveViewer(
                                                                child: CachedNetworkImage(
                                                                  imageUrl: msg['imageUrl'] ?? '',
                                                                  fit: BoxFit.contain,
                                                                  placeholder: (context, url) => const Center(
                                                                    child: CircularProgressIndicator(),
                                                                  ),
                                                                  errorWidget: (context, url, error) => const Icon(
                                                                    Icons.error,
                                                                    color: Colors.red,
                                                                  ),
                                                                ),
                                                              ),
                                                              Positioned(
                                                                right: 4,
                                                                top: 4,
                                                                child: GestureDetector(
                                                                  onTap: () {
                                                                    Navigator.of(context).pop();
                                                                  },
                                                                  child: Container(
                                                                    decoration: BoxDecoration(
                                                                      color: Colors.black54,
                                                                      shape: BoxShape.circle,
                                                                    ),
                                                                    padding: const EdgeInsets.all(4),
                                                                    child: const Icon(
                                                                      Icons.close,
                                                                      size: 18,
                                                                      color: Colors.white,
                                                                    ),
                                                                  ),
                                                                ),
                                                              ),
                                                            ],
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                    child: ClipRRect(
                                                      borderRadius: BorderRadius.only(
                                                        topLeft: Radius.circular(isMe ? 16 : (sameAsPrev ? 4 : 16)),
                                                        topRight: Radius.circular(isMe ? (sameAsPrev ? 4 : 16) : 16),
                                                        bottomLeft: Radius.circular(isMe ? 16 : (sameAsNext ? 4 : 16)),
                                                        bottomRight: Radius.circular(isMe ? (sameAsNext ? 4 : 16) : 16),
                                                      ),
                                                      child: CachedNetworkImage(
                                                        imageUrl: msg['imageUrl'] ?? '',
                                                        width: 180,
                                                        height: 180,
                                                        fit: BoxFit.cover,
                                                        placeholder: (context, url) => Container(
                                                          width: 180,
                                                          height: 180,
                                                          child: const Center(
                                                            child: CircularProgressIndicator(),
                                                          ),
                                                        ),
                                                        errorWidget: (context, url, error) => const Icon(
                                                          Icons.error,
                                                          color: Colors.red,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              )
                                            : Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                decoration: BoxDecoration(
                                                  color: isMe ? const Color(0xFF89C9C2) : const Color(0xFFF6DBDC),
                                                  borderRadius: BorderRadius.only(
                                                    topLeft: Radius.circular(isMe ? 16 : (sameAsPrev ? 4 : 16)),
                                                    topRight: Radius.circular(isMe ? (sameAsPrev ? 4 : 16) : 16),
                                                    bottomLeft: Radius.circular(isMe ? 16 : (sameAsNext ? 4 : 16)),
                                                    bottomRight: Radius.circular(isMe ? (sameAsNext ? 4 : 16) : 16),
                                                  ),
                                                ),
                                                child: Text(
                                                  msg['text'] ?? '',
                                                  style: const TextStyle(fontSize: 14),
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
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // // 編輯按鈕
                // ElevatedButton.icon(
                //   style: ElevatedButton.styleFrom(
                //     backgroundColor: Colors.white70,
                //     foregroundColor: Colors.black,
                //   ),
                //   icon: const Icon(Icons.edit),
                //   label: const Text("編輯"),
                //   onPressed: () async {
                //     try {
                //       // 讀取圖片成 Uint8List
                //       Uint8List imageBytes = await originalImage.readAsBytes();

                //       // 開啟 image_editor_plus 編輯器
                //       final editedBytes = await Navigator.push<Uint8List?>(
                //         context,
                //         MaterialPageRoute(
                //           builder: (context) => ImageEditor(
                //             image: imageBytes,
                //           ),
                //         ),
                //       );

                //       if (editedBytes != null) {
                //         // 將 Uint8List 存成暫存檔
                //         final tempDir = await getTemporaryDirectory();
                //         final editedFile =
                //             File('${tempDir.path}/edited_image.png');
                //         await editedFile.writeAsBytes(editedBytes);

                //         Navigator.pop(context, editedFile);
                //       }
                //     } catch (e) {
                //       print('圖片編輯錯誤: $e');
                //     }
                //   },
                // ),
                // 傳送按鈕
                SizedBox(
                  width: 70,
                  height: 70,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: Color(0xFFD1F5F1),
                      padding: EdgeInsets.all(4),
                      side: BorderSide(color: Colors.black, width: 2),
                    ),
                    onPressed: () {
                      Navigator.pop(context, originalImage);
                    },
                    child: Image.asset('assets/airplane.png')
                  ),
                ),
              ],
            ),
          ),
          // 關閉按鈕
          Positioned(
            top: 40,
            left: 20,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white, size: 30),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ],
      ),
    );
  }
}
