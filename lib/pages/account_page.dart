import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../main.dart';

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final nameController = TextEditingController();
  final bioController = TextEditingController();
  final birthdayController = TextEditingController();
  String email = '';
  String? photoURL;
  List<String> tags = [];
  String gender = '';
  String? genderDetail;
  String orientation = '';
  String? mbti;
  String? zodiac;
  String school = '';
  bool isLoading = true;

  final List<String> mbtiList = [
    'ISTJ', 'ISFJ', 'INFJ', 'INTJ',
    'ISTP', 'ISFP', 'INFP', 'INTP',
    'ESTP', 'ESFP', 'ENFP', 'ENTP',
    'ESTJ', 'ESFJ', 'ENFJ', 'ENTJ',
  ];

  final List<String> zodiacList = [
    '牡羊座', '金牛座', '雙子座', '巨蟹座', '獅子座', '處女座',
    '天秤座', '天蠍座', '射手座', '摩羯座', '水瓶座', '雙魚座',
  ];

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (doc.exists) {
      final data = doc.data()!;
      nameController.text = data['name'] ?? '';
      birthdayController.text = data['birthday'] ?? '';
      bioController.text = data['bio'] ?? '';
      email = data['email'] ?? user.email ?? '';
      photoURL = user.photoURL;
      tags = List<String>.from(data['tags'] ?? []);
      gender = data['gender'] ?? '';
      genderDetail = data['genderDetail'];
      orientation = data['orientation'] ?? '';
      mbti = data['mbti'];
      zodiac = data['zodiac'];
      school = data['school'] ?? '';
    }

    setState(() {
      isLoading = false;
    });
  }

  Future<void> _saveProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'name': nameController.text.trim(),
      'bio': bioController.text.trim(),
      'birthday': birthdayController.text.trim(),
      'mbti': mbti,
      'zodiac': zodiac,
      'tags': tags,
    });

    if (context.mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('個人資料已更新')),
      );
    }
  }

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
            return Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: ListView(
                children: [
                  const Text('編輯個人資料',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
                  TextField(
                    controller: birthdayController,
                    readOnly: true,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now().subtract(const Duration(days: 365 * 20)),
                        firstDate: DateTime(1900),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        birthdayController.text =
                            '${picked.year}/${picked.month.toString().padLeft(2, '0')}/${picked.day.toString().padLeft(2, '0')}';
                      }
                    },
                    decoration: const InputDecoration(labelText: '生日'),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: mbti,
                    items: mbtiList.map((type) => DropdownMenuItem(
                      value: type,
                      child: Text(type),
                    )).toList(),
                    onChanged: (value) => setModalState(() => mbti = value),
                    decoration: const InputDecoration(labelText: 'MBTI'),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: zodiac,
                    items: zodiacList.map((sign) => DropdownMenuItem(
                      value: sign,
                      child: Text(sign),
                    )).toList(),
                    onChanged: (value) => setModalState(() => zodiac = value),
                    decoration: const InputDecoration(labelText: '星座'),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 4,
                    children: [
                      for (final tag in tags)
                        Chip(
                          label: Text(tag),
                          onDeleted: () {
                            setState(() => tags.remove(tag));
                            setModalState(() {});
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
                              content: TextField(controller: controller),
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
                                      setModalState(() {});
                                    }
                                    Navigator.pop(context);
                                  },
                                  child: const Text('新增'),
                                ),
                              ],
                            ),
                          );
                        },
                      )
                    ],
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _saveProfile,
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
            );
          },
        );
      },
    );
  }

  Widget buildProfileDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (birthdayController.text.isNotEmpty)
          Text('🎂 生日：${birthdayController.text}'),
        if (gender.isNotEmpty)
          Text('👤 性別：$gender${genderDetail != null ? "（$genderDetail）" : ""}'),
        if (orientation.isNotEmpty) Text('🌈 性向：$orientation'),
        if (mbti != null) Text('🧠 MBTI：$mbti'),
        if (zodiac != null) Text('♈ 星座：$zodiac'),
        if (school.isNotEmpty) Text('🏫 學校：$school'),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const Center(child: CircularProgressIndicator());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
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
          buildProfileDetails(),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final tag in tags)
                Chip(
                  label: Text(tag, style: const TextStyle(fontSize: 12)),
                  backgroundColor: Colors.blue.shade100,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => showEditBottomSheet(context),
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
