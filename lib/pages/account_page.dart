import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../main.dart'; // 或調整為你 WelcomePage 的正確路徑

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final nameController = TextEditingController();
  final bioController = TextEditingController();
  bool isLoading = true;
  bool isEditing = false;
  String email = '';
  String? photoURL;
  List<String> tags = [];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  // 新增標籤
  Future<void> addTag(String newTag) async {
    if (newTag.trim().isEmpty) return;
    if (tags.contains(newTag)) return; // 已存在就不新增

    setState(() {
      tags.add(newTag.trim());
    });
  }

  // 新增標籤時跳出來的對話框
  void showAddTagDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新增標籤'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: '輸入新標籤...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () {
              final newTag = controller.text;
              Navigator.pop(context);
              addTag(newTag);
            },
            child: const Text('新增'),
          ),
        ],
      ),
    );
  }

  // 取得firebase中的資料
  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

    if (doc.exists) {
      final data = doc.data()!;
      nameController.text = data['name'] ?? '';
      bioController.text = data['bio'] ?? '';
      email = data['email'] ?? user.email ?? '';
      photoURL = user.photoURL;
      tags = List<String>.from(doc.data()?['tags'] ?? []);
    }

    setState(() {
      isLoading = false;
    });
  }

  // 更新資料進入firebase
  Future<void> _saveProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final name = nameController.text.trim();
    final bio = bioController.text.trim();

    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'name': name,
      'bio': bio,
      'tags': tags,
    });

    setState(() {
      isEditing = false;
    });

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('個人資料已更新')),
      );
    }
  }

  // 登出
  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    await GoogleSignIn().signOut();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const WelcomePage()),
        (route) => false,
      );
    }
  }

  // 編輯個人資料頁面
  void showEditBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SizedBox.expand(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 24,
                  right: 24,
                  top: 24,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('編輯個人資料',
                        style:
                            TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: '名稱'),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: bioController,
                      decoration: const InputDecoration(labelText: '簡介'),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      runAlignment: WrapAlignment.start,
                      children: [
                        for (final tag in tags)
                          Chip(
                            label: Text(tag, style: const TextStyle(fontSize: 12)),
                            backgroundColor: Colors.blue.shade100,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            onDeleted: () {
                              setState(() => tags.remove(tag));
                              setModalState(() {}); // ✅ 更新 bottom sheet 畫面
                            },
                          ),
                        ActionChip(
                          avatar: const Icon(Icons.add),
                          label: const Text('新增'),
                          onPressed: () {
                            final controller = TextEditingController();
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('新增標籤'),
                                content: TextField(
                                  controller: controller,
                                  decoration: const InputDecoration(hintText: '輸入新標籤...'),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(context),
                                    child: const Text('取消'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () {
                                      final newTag = controller.text.trim();
                                      if (newTag.isNotEmpty && !tags.contains(newTag)) {
                                        setState(() => tags.add(newTag));
                                        setModalState(() {}); // ✅ 更新 bottom sheet 畫面
                                      }
                                      Navigator.pop(context);
                                    },
                                    child: const Text('新增'),
                                  ),
                                ],
                              ),
                            );
                          },
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      onPressed: () async {
                        await _saveProfile();
                        if (context.mounted) Navigator.pop(context);
                      },
                      icon: const Icon(Icons.save),
                      label: const Text('儲存變更'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.pink,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          Row(
            children: [CircleAvatar(
                radius: 35,
                backgroundImage: photoURL != null ? NetworkImage(photoURL!) : null,
                child: photoURL == null ? const Icon(Icons.person, size: 40) : null,
              ),
              const SizedBox(width: 32),
              Text(
                nameController.text.isNotEmpty ? nameController.text : '未設定名稱',
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),

              ),
            ],
          ),
          
          const SizedBox(height: 16),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            runAlignment: WrapAlignment.start,
            children: [
              for (final tag in tags)
                Chip(
                  label: Text(tag, style: TextStyle(fontSize: 12),),
                  backgroundColor: Colors.blue.shade100,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16), // 數字越大越圓
                  ),
                  onDeleted: isEditing
                      ? () async {
                          setState(() {
                            tags.remove(tag);
                          });
                          final user = FirebaseAuth.instance.currentUser;
                          if (user != null) {
                            await FirebaseFirestore.instance
                                .collection('users')
                                .doc(user.uid)
                                .update({'tags': tags});
                          }
                        }
                      : null,
                ),
            ],
          ),

          const SizedBox(height: 24),

          ElevatedButton.icon(
            onPressed: () {
              showEditBottomSheet(context);
            },
            // {
            //   setState(() {
            //     isEditing = true;
            //   });
            // },
            icon: const Icon(Icons.edit),
            label: const Text('編輯個人資料'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.pink,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
            ),
          ),

          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            label: const Text('登出'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              side: const BorderSide(color: Colors.pink),
              foregroundColor: Colors.pink,
            ),
          ),
        ],
      ),
    );
  }
}
