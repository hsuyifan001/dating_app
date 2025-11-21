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
import 'package:dating_app/utils/notification_util.dart';

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
      // 使用 docChanges 處理新增/修改/移除，確保離開群組時會移除列表中的聊天室
      for (final change in snapshot.docChanges) {
        final doc = change.doc;
        if (change.type == DocumentChangeType.removed) {
          _chatDocs.removeWhere((d) => d.id == doc.id);
        } else if (change.type == DocumentChangeType.modified) {
          final index = _chatDocs.indexWhere((c) => c.id == doc.id);
          if (index >= 0) {
            _chatDocs[index] = doc;
          } else {
            _chatDocs.insert(0, doc);
          }
        } else if (change.type == DocumentChangeType.added) {
          final index = _chatDocs.indexWhere((c) => c.id == doc.id);
          if (index >= 0) {
            _chatDocs[index] = doc;
          } else {
            _chatDocs.insert(0, doc);
          }
        }
      }

      // 判斷是否還有更多資料
      _hasMore = (snapshot.docs.length >= _limit);

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
                        myPhotoUrl = displayPhotos.entries
                          .firstWhere((entry) => entry.key != uid, orElse: () => const MapEntry('', ''))
                          .value;
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
  bool _isBlocked = false; // 聊天室是否被封鎖
  String _chatType = '';
  StreamSubscription<DocumentSnapshot>? _chatDocSub;
  List<Map<String, dynamic>> _localTempMessages = [];

  @override
  void initState() {
    super.initState();
    _loadChatInfo();
    // 監聽聊天室 doc 以即時更新 displayPhotos、封鎖狀態與 type
    _chatDocSub = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatRoomId)
        .snapshots()
        .listen((doc) {
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        setState(() {
          _displayPhotos = (data['displayPhotos'] as Map<String, dynamic>?) ?? _displayPhotos;
          _isBlocked = data['block'] == true;
          _chatType = data['type'] ?? '';
        });
      }
    });
  }

  @override
  void dispose() {
    _chatDocSub?.cancel();
    _scrollController.dispose();
    messageController.dispose();
    super.dispose();
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

    // 若聊天室被封鎖，阻止發送
    if (_isBlocked) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('此聊天室已被封鎖，無法發送訊息')));
      return;
    }

    try {
      // 發送訊息
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

      // 更新聊天室
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatRoomId)
          .update({
        'lastMessage': text,
        'lastMessageTime': FieldValue.serverTimestamp(),
      });

      // 獲取聊天室資料
      final chatDoc = await FirebaseFirestore.instance.collection('chats').doc(widget.chatRoomId).get();
      if (!chatDoc.exists) {
        print('聊天室 ${widget.chatRoomId} 不存在');
        return;
      }
      final members = List<String>.from(chatDoc['members'] ?? []);
      final type = chatDoc['type'] ?? '';
      final groupName = chatDoc['groupName'] ?? '群組聊天'; // 預設值

      for (final targetUserId in members) {
        if (targetUserId != currentUser!.uid) {
          final title = type == 'activity'
              ? groupName
              : (chatDoc['displayNames']?[targetUserId] ?? '某人');
          await sendPushNotification(
            fromUserId: currentUser!.uid,
            targetUserId: targetUserId,
            title: title.isEmpty ? '群組聊天' : title, // 確保標題非空
            body: text,
            data: {
              'type': 'chat',
              'chatRoomId': widget.chatRoomId,
            },
          );
        }
      }
    } catch (e) {
      print('發送訊息或通知失敗: $e');
      // if (context.mounted) {
      //   ScaffoldMessenger.of(context).showSnackBar(
      //     SnackBar(content: Text('發送訊息失敗：$e')),
      //   );
      // }
    }
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
    // 若聊天室被封鎖，阻止上傳圖片
    if (_isBlocked) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('此聊天室已被封鎖，無法上傳圖片')));
      return;
    }
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
      // ScaffoldMessenger.of(context).showSnackBar(
      //   SnackBar(content: Text('圖片上傳失敗: $e')),
      // );
      _removeTempImageMessage(tempId);
    }
  }

  // 將另一個使用者在 users/{userId} 底下的 matches <-> blocked 移動
  Future<void> _moveBetweenCollections(String userId, String otherId, {required bool toBlocked}) async {
    final userRef = FirebaseFirestore.instance.collection('users').doc(userId);
    final matchesRef = userRef.collection('matches').doc(otherId);
    final blockedRef = userRef.collection('blocked').doc(otherId);

    if (toBlocked) {
      final matchDoc = await matchesRef.get();
      if (matchDoc.exists) {
        final data = matchDoc.data();
        await blockedRef.set(data ?? {'userId': otherId, 'createdAt': FieldValue.serverTimestamp()});
        await matchesRef.delete();
      } else {
        await blockedRef.set({'userId': otherId, 'createdAt': FieldValue.serverTimestamp()});
      }
    } else {
      final blockedDoc = await blockedRef.get();
      if (blockedDoc.exists) {
        final data = blockedDoc.data();
        await matchesRef.set(data ?? {'userId': otherId, 'createdAt': FieldValue.serverTimestamp()});
        await blockedRef.delete();
      } else {
        await matchesRef.set({'userId': otherId, 'createdAt': FieldValue.serverTimestamp()});
      }
    }
  }

  // 切換封鎖狀態（針對 type == 'match' 的聊天室）
  Future<void> _toggleBlock(bool block) async {
    try {
      final chatRef = FirebaseFirestore.instance.collection('chats').doc(widget.chatRoomId);
      final chatDoc = await chatRef.get();
      if (!chatDoc.exists) return;
      final data = chatDoc.data() as Map<String, dynamic>? ?? {};
      final members = List<String>.from(data['members'] ?? []);

      // 更新 chat doc 的 block 布林值
      await chatRef.update({'block': block});

      // 對每個成員，將對方從 matches 移到 blocked（或相反）
      for (final userId in members) {
        final otherId = members.firstWhere((id) => id != userId, orElse: () => '');
        if (otherId.isEmpty) continue;
        await _moveBetweenCollections(userId, otherId, toBlocked: block);
      }

      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(block ? '已封鎖對方' : '已解除封鎖')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作失敗：$e')));
    }
  }

  // 退出群組（只針對 type == 'activity'）
  Future<void> _leaveGroup() async {
    try {
      final chatRef = FirebaseFirestore.instance.collection('chats').doc(widget.chatRoomId);
      final chatDocSnap = await chatRef.get();
      if (!chatDocSnap.exists) return;
      final data = chatDocSnap.data() as Map<String, dynamic>? ?? {};
      final members = List<String>.from(data['members'] ?? []);

      // 移除當前使用者
      final updatedMembers = members.where((id) => id != currentUser!.uid).toList();

      // 更新 displayPhotos map
      final displayPhotos = Map<String, dynamic>.from(data['displayPhotos'] ?? {});
      displayPhotos.remove(currentUser!.uid);

      if (updatedMembers.isEmpty) {
        // 若無其他成員，刪除整個聊天室
        await chatRef.delete();
      } else {
        await chatRef.update({
          'members': updatedMembers,
          'displayPhotos': displayPhotos,
        });
      }

      if (mounted) {
        // 重新載入聊天室資料以更新目前聊天室資訊
        await _loadChatInfo();
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已成功退出群組')));
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('退出群組失敗：$e')));
    }
  }

  /// 顯示檢舉表單（下拉選擇被檢舉對象、原因，並可上傳多張圖片與文字說明）
  Future<void> showReportMenu(BuildContext context, String currentUserId, String chatRoomId) async {
    try {
      // 取得聊天室資料
      final chatDoc = await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatRoomId)
          .get();

      if (!chatDoc.exists) {
        print('聊天室 $chatRoomId 不存在');
        return;
      }

      // 取得成員列表（排除自己）
      final members = List<String>.from(chatDoc['members'] ?? []);
      final reportTargets = members.where((id) => id != currentUserId).toList();

      if (reportTargets.isEmpty) {
        print('沒有可檢舉的成員');
        return;
      }

      // 抓取成員的名字
      final List<Map<String, String>> usersInfo = [];
      for (final userId in reportTargets) {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .get();
        if (userDoc.exists) {
          usersInfo.add({
            'id': userId,
            'name': userDoc['name'] ?? '未命名使用者',
          });
        }
      }

      if (usersInfo.isEmpty) {
        print('無法取得被檢舉使用者資訊');
        return;
      }

      // 將表單狀態提升到此作用域，避免系統在鍵盤彈出/收起時重新執行 builder 導致狀態重置
      String? selectedTargetId = usersInfo.first['id'];
      String? selectedReason;
      final TextEditingController descController = TextEditingController();
      bool isSubmitting = false;

      // 顯示可滾動的表單 bottom sheet（await 後再 dispose controller）
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (context) {
          return StatefulBuilder(builder: (context, setState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('檢舉使用者', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: selectedTargetId,
                        items: usersInfo.map((u) => DropdownMenuItem(
                          value: u['id'],
                          child: Text(u['name'] ?? '未命名'),
                        )).toList(),
                        onChanged: (v) => setState(() => selectedTargetId = v),
                        decoration: const InputDecoration(border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),

                      const Text('檢舉原因', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: selectedReason,
                        items: const [
                          DropdownMenuItem(value: 'CSAE', child: Text('兒少安全問題')),
                          DropdownMenuItem(value: 'Impersonation', child: Text('冒充身分')),
                          DropdownMenuItem(value: 'Inappropriate Content', child: Text('不當內容')),
                        ],
                        onChanged: (v) => setState(() => selectedReason = v),
                        decoration: const InputDecoration(border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 12),

                      // 圖片上傳功能暫時關閉以避免伺服器風險
                      const SizedBox(height: 12),

                      const Text('說明（選填）', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      TextField(
                        controller: descController,
                        minLines: 2,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: '請描述發生了什麼事（可附上時間/聊天室內容）',
                        ),
                      ),
                      const SizedBox(height: 16),

                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: isSubmitting ? null : () => Navigator.of(context).pop(),
                            child: const Text('取消'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: isSubmitting ? null : () async {
                              if (selectedTargetId == null || selectedReason == null) {
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請選擇被檢舉對象與原因')));
                                return;
                              }
                              setState(() => isSubmitting = true);
                              await _submitReport(
                                context,
                                currentUserId,
                                selectedTargetId!,
                                selectedReason!,
                                description: descController.text.trim(),
                                chatRoomId: chatRoomId,
                              );
                              if (mounted) Navigator.of(context).pop();
                            },
                            child: const Text('送出檢舉'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          });
        },
      );

  // 不主動 dispose controller（避免在某些情況下因依賴尚未移除而發生 AssertionError）
    } catch (e) {
      // ignore
    }
  }


  

/// 寫入 Firestore（支援 description、多張圖片與 chatRoomId）
Future<void> _submitReport(
  BuildContext context,
  String reporterId,
  String reportedUserId,
  String reason, {
  String? description,
  String? chatRoomId,
}) async {
  try {
    final reportsRef = FirebaseFirestore.instance.collection('reports');
    final docRef = reportsRef.doc();

    // 先建立 report doc（imageUrls 先空），之後會更新 imageUrls
    await docRef.set({
      'reporterId': reporterId,
      'reportedUserId': reportedUserId,
      'reason': reason,
      'description': description ?? '',
      'chatRoomId': chatRoomId ?? '',
      'imageUrls': [],
      'createdAt': FieldValue.serverTimestamp(),
    });

    // 圖片上傳功能已停用（避免伺服器風險）

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已送出檢舉')));
    }
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('檢舉失敗，請稍後再試')));
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
                    child: PopupMenuButton<String>(
                      icon: const Icon(Icons.more_vert),
                      onSelected: (value) async {
                        try {
                          if (value == 'report') {
                            await showReportMenu(context, currentUser!.uid, widget.chatRoomId);
                          } else if (value == 'block') {
                            // 確認封鎖
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('封鎖使用者'),
                                content: const Text('封鎖後將無法在此聊天室發送訊息，並會把對方移到封鎖名單。確定要封鎖嗎？'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
                                  TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('確定')),
                                ],
                              ),
                            );
                            if (confirmed == true) await _toggleBlock(true);
                          } else if (value == 'unblock') {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('解除封鎖'),
                                content: const Text('解除封鎖後會將對方移回配對列表，並可以在聊天室發送訊息。確定要解除封鎖嗎？'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
                                  TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('確定')),
                                ],
                              ),
                            );
                            if (confirmed == true) await _toggleBlock(false);
                            } else if (value == 'leave') {
                              final confirmed = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('退出群組'),
                                  content: const Text('你確定要退出此群組嗎？退出後你將不會收到此群組訊息。'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
                                    TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('確定')),
                                  ],
                                ),
                              );
                              if (confirmed == true) await _leaveGroup();
                          }
                        } catch (e) {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('操作失敗：$e')));
                        }
                      },
                      itemBuilder: (context) {
                        final items = <PopupMenuEntry<String>>[];
                        items.add(const PopupMenuItem(value: 'report', child: Text('檢舉')));
                        if (_chatType == 'match') {
                          if (_isBlocked) {
                            items.add(const PopupMenuItem(value: 'unblock', child: Text('解除封鎖')));
                          } else {
                            items.add(const PopupMenuItem(value: 'block', child: Text('封鎖使用者')));
                          }
                        }
                        if (_chatType == 'activity') {
                          items.add(const PopupMenuItem(value: 'leave', child: Text('退出群組')));
                        }
                        return items;
                      },
                    ),
                  ),
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
                      image: AssetImage('assets/chat_background.jpg'),
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
