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
  final user = FirebaseAuth.instance.currentUser;
  String email = '';
  String? photoURL ;
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
      photoURL = data['photoUrl'] ;
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

  /*Widget buildProfileDetails() {
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
  }*/

  // 新增標題區塊widget
  Widget buildTitleBlock(double screenWidth, double screenHeight) {
    double pxW(double px) => screenWidth * (px / 412);
    double pxH(double px) => screenHeight * (px / 917);

    return SizedBox(
      width: pxW(387),
      height: pxH(64),
      child: Stack(
        children: [
          // Icon 圖片
          Positioned(
            left: pxW(7),
            top: pxH(5),
            width: pxW(52),
            height: pxH(52),
            child: Image.asset('assets/qing.png', fit: BoxFit.contain),
          ),

          // 文字「個人資料」
          Positioned(
            left: pxW(25),
            top: pxH(11),
            width: pxW(164),
            height: pxH(41),
            child: const Center(
              child: Text(
                '個人資料',
                style: TextStyle(
                  fontFamily: 'Kiwi Maru',
                  fontWeight: FontWeight.w500,
                  fontSize: 24,
                  height: 1,
                  letterSpacing: 0,
                  color: Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),

          // 三個點
          Positioned(
            left: pxW(347),
            top: pxH(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (index) {
                return Container(
                  width: pxW(6.35),
                  height: pxH(6.35),
                  margin: EdgeInsets.only(bottom: index < 2 ? pxH(8.89) : 0),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.black, width: 2),
                    shape: BoxShape.circle,
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildSelfprofileBlock(double screenWidth, double screenHeight) {
    return Container(
      width: screenWidth * (387 / 412),
      height: screenHeight * (694 / 917),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.black, width: 2),
      ),
      child: Stack(
        children: [
          // 個人頭像
          Positioned(
            top: screenHeight * (26 / 917),
            left: screenWidth * (26 / 412),
            width: screenWidth * (102 / 412),
            height: screenHeight * (102 / 917),
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color.fromRGBO(255, 200, 202, 1),
                  width: 5,
                ),
              ),
              child: CircleAvatar(
                backgroundImage: (user == null && user!.data['photoUrl'] != null)
                    ? NetworkImage(photoURL!)
                    : const AssetImage('assets/match_default.jpg') as ImageProvider,
                backgroundColor: Colors.transparent,
              )
            ),
          ),

          // 使用者姓名文字框
          Positioned(
            top: screenHeight * (64 / 917),
            left: screenWidth * (120 / 412),
            width: screenWidth * (147 / 412),
            height: screenHeight * (41 / 917),
            child: Center(
              child: Text(
                nameController.text.isNotEmpty ? nameController.text : '未設定名稱',
                style: const TextStyle(
                  fontFamily: 'Kiwi Maru',
                  fontWeight: FontWeight.w500,
                  fontSize: 24,
                  height: 1,
                  letterSpacing: 0,
                  color: Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),

          // 旋轉 icon.png
          Positioned(
            top: screenHeight * (4 / 917),
            left: screenWidth * (232 / 412),
            width: screenWidth * (149 / 412),
            height: screenHeight * (149 / 917),
            child: Transform.rotate(
              angle: 14.53 * 3.1415926535 / 180, // 角度轉弧度
              child: Opacity(
                opacity: 1,
                child: Image.asset(
                  'assets/icon.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),

          // 學校標題文字
          Positioned(
            top: screenHeight * (167 / 917),
            left: screenWidth * (3 / 412),
            width: screenWidth * (147 / 412),
            height: screenHeight * (41 / 917),
            child: Center(
              child: Text(
                '學校：',
                style: const TextStyle(
                  fontFamily: 'Kiwi Maru',
                  fontWeight: FontWeight.w500,
                  fontSize: 24,
                  height: 1,
                  letterSpacing: 0,
                  color: Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),

          // 性別標題文字
          Positioned(
            top: screenHeight * (198 / 917),
            left: screenWidth * (3 / 412),
            width: screenWidth * (147 / 412),
            height: screenHeight * (41 / 917),
            child: Center(
              child: Text(
                '性別：',
                style: const TextStyle(
                  fontFamily: 'Kiwi Maru',
                  fontWeight: FontWeight.w500,
                  fontSize: 24,
                  height: 1,
                  letterSpacing: 0,
                  color: Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),

          // 自我介紹文字框（標題）
          Positioned(
            top: screenHeight * (231 / 917),
            left: screenWidth * (0 / 412),
            width: screenWidth * (168 / 412),
            height: screenHeight * (41 / 917),
            child: Center(
              child: Text(
                '自我介紹:',
                style: const TextStyle(
                  fontFamily: 'Kiwi Maru',
                  fontWeight: FontWeight.w500,
                  fontSize: 24,
                  height: 1,
                  letterSpacing: 0,
                  color: Colors.black,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),

          // 自我介紹內容
          Positioned(
            top: screenHeight * (275 / 917),
            left: screenWidth * (58 / 412),
            right: screenWidth * (10 / 412),
            
            child: Text(
              bioController.text.isNotEmpty ? bioController.text : '尚未填寫自我介紹',
              style: const TextStyle(
                fontSize: 16,
                color: Colors.black87,
              ),
            ),
          ),
          for (int i = 0; i < (tags.length > 6 ? 6 : tags.length); i++)
            Positioned(
              top: screenHeight * ( (308 + (i ~/ 3) * (39 + 9) )/ 917),
              left: screenWidth * ( (30 + (i % 3) * (104 + 8) ) / 412),
              width: screenWidth * (104 / 412),
              height: screenHeight * (39 / 917),
              
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.pink.shade100, width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.pink.shade50,
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Text(
                  tags[i].toString(),
                  style: const TextStyle(
                    color: Colors.pink,
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          // 編輯個人資料按鈕
          Positioned(
            top: screenHeight * (500 / 917),
            left: screenWidth * (26 / 412),
            width: screenWidth * (156 / 412),
            height: screenHeight * (55 / 917),
            child: ElevatedButton(
              onPressed: () => showEditBottomSheet(context),
              style: ElevatedButton.styleFrom(
              backgroundColor: const Color.fromRGBO(255, 200, 202, 1),
              foregroundColor: Colors.black, // 文字顏色
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(30),
                side: const BorderSide(
                  color: Color.fromRGBO(0, 0, 0, 1),
                  width: 2,
                ),
              ),
            ),
              child: const Text(
              '編輯個人資料',
              style: TextStyle(
                fontFamily: 'Kiwi Maru',
                fontWeight: FontWeight.w500,
                fontSize: 20,
                height: 1.0, // line-height: 100%
                letterSpacing: 0.0,
              ),
              textAlign: TextAlign.center,
            ),
            ),
          ),

          // 登出按鈕
          Positioned(
            top: screenHeight * (500 / 917),
            left: screenWidth * (213 / 412),
            width: screenWidth * (156 / 412),
            height: screenHeight * (55 / 917),
            child: ElevatedButton(
              onPressed: _logout,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color.fromRGBO(255, 255, 255, 1),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                  side: const BorderSide(
                    color: Color.fromRGBO(0, 0, 0, 1),
                    width: 2,
                  ),
                ),
              ),
              child: const Text(
                '登出',
                style: TextStyle(
                  color: Color.fromRGBO(246, 157, 158, 1),
                  fontFamily: 'Kiwi Maru',
                  fontWeight: FontWeight.w500,
                  fontSize: 20,
                  height: 1.0, // line-height: 100%
                  letterSpacing: 0.0,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          Positioned(
            top: screenHeight * (580 / 917), // 登出按鈕下方
            left: screenWidth * (10 / 412),
            width: screenWidth * (392 / 412),
            height: screenHeight * (300 / 917), // 高度可自行調整
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user!.uid) // 只抓自己的
                  .collection('stories')
                  .orderBy('timestamp', descending: true) // 依時間排序
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('目前沒有動態'));
                }

                final stories = snapshot.data!.docs.map((doc) {
                  return {
                    ...doc.data() as Map<String, dynamic>,
                    'storyId': doc.id,
                  };
                }).toList();

                return ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: stories.length,
                  itemBuilder: (context, index) {
                    return _buildStoryCard(stories[index]);
                  },
                );
              },
            ),
          ),

        ],
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    if (isLoading) return const Center(child: CircularProgressIndicator());

    return Scaffold(
      backgroundColor: Colors.grey[200],
      body: Stack(
        children: [
          // 上方標題區塊長方形底色（含陰影、邊框）
          Positioned(
            top: screenHeight * (29 / 917),
            left: (screenWidth - (screenWidth * (387 / 412))) / 2,
            child: Container(
              width: screenWidth * (387 / 412),
              height: screenHeight * (64 / 917),
              decoration: BoxDecoration(
                color: const Color.fromRGBO(255, 200, 202, 1),
                border: Border.all(color: Colors.black, width: 2),
                borderRadius: BorderRadius.circular(10),
                boxShadow: const [
                  BoxShadow(
                    color: Color.fromRGBO(0, 0, 0, 0.25),
                    offset: Offset(0, 4),
                    blurRadius: 4,
                  ),
                ],
              ),
              // 內部放標題區塊細節UI
              child: buildTitleBlock(screenWidth, screenHeight),
            ),
          ),

          // 下方個人資料區塊長方形底色
          Positioned(
            top: screenHeight * (104 / 917),
            left: (screenWidth - (screenWidth * (387 / 412))) / 2,
            child: Container(
              width: screenWidth * (387 / 412),
              height: screenHeight * (694 / 917),
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border.all(color: Colors.black, width: 2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: buildSelfprofileBlock(screenWidth, screenHeight),
            ),
          ),
        ],
      ),
    );
  }
}

extension on User {
  get data => null;
}
