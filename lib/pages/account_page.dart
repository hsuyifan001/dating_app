import 'package:dating_app/profile_setup_page.dart';
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
  String selfIntro = '';
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
      selfIntro = data['selfIntro'] ?? '';
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
    //double pxW(double px) => screenWidth * (px / 412);
    //double pxH(double px) => screenHeight * (px / 917);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Expanded(
          flex: 1,
          child: Image(
            image: AssetImage('assets/qing.png'),
            width: 22,
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(
          flex: 6,
          child: Text(
            "個人資料",
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
    );
  }

  Widget buildSelfprofileBlock(double screenWidth, double screenHeight) {
  // 基準尺寸 (Figma 畫布)
  const baseWidth = 412.0;
  const baseHeight = 917.0;

  // 依據螢幕比例計算縮放
  double w(double value) => value * screenWidth / baseWidth;
  double h(double value) => value * screenHeight / baseHeight;


  final double tagWidth = w(104);
  final double tagSpacing = w(12);


  // 計算一列最多三個標籤，三個標籤加兩個間距的寬度
  final double maxWrapWidth = tagWidth * 3 + tagSpacing * 2;

  return SingleChildScrollView(
    padding: EdgeInsets.all(w(14)),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: h(10)),

        // 頭像 + 姓名 + icon 疊加
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 頭像
            Container(
              width: w(102),
              height: w(102),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: const Color.fromRGBO(255, 200, 202, 1),
                  width: 5,
                ),
              ),
              child: CircleAvatar(
                backgroundImage: (user != null &&
                        user!.data != null &&
                        user!.data["photoUrl"] != null)
                    ? NetworkImage(photoURL!)
                    : const AssetImage('assets/match_default.jpg') as ImageProvider,
                backgroundColor: Colors.transparent,
              ),
            ),

            SizedBox(width: w(15)),

            // 姓名區域，Expanded 保證不超出可用寬度
            Expanded(
              child: SizedBox(
                height: w(102),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      nameController.text.isNotEmpty
                          ? nameController.text
                          : '未設定名稱',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'Kiwi Maru',
                        fontWeight: FontWeight.w500,
                        fontSize: 24,
                        color: Colors.black,
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // icon，固定大小並放在Row右側
            SizedBox(
              width: w(102), // 可依需求微調
              height: w(102),
              child: Transform.rotate(
                angle: 14.53 * 3.1415926535 / 180,
                child: Image.asset(
                  'assets/icon.png',
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ],
        ),


        SizedBox(height: h(60)),

        Transform.translate(
          offset: Offset( w(20) , 0), // 向左移動5像素

          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: h(30), // 你可以根據需要調整大小
                child: FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '學校：$school${school.isNotEmpty ? '' : '尚未填寫'}',
                    style: const TextStyle(
                      fontFamily: 'Kiwi Maru',
                      fontWeight: FontWeight.w500,
                      fontSize: 30, // 這會是最大字級，實際字號會依盒子大小縮放
                      color: Colors.black,
                    ),
                  ),
                ),
              ),

              SizedBox(height: h(8)),

              SizedBox(
                height: h(30),
                child: FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '性別：$gender${gender.isNotEmpty ? '' : '尚未填寫'}',
                    style: const TextStyle(
                      fontFamily: 'Kiwi Maru',
                      fontWeight: FontWeight.w500,
                      fontSize: 30,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),

              SizedBox(height: h(8)),

              SizedBox(
                height: h(30),
                child: FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '自我介紹:',
                    style: const TextStyle(
                      fontFamily: 'Kiwi Maru',
                      fontWeight: FontWeight.w500,
                      fontSize: 30,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),

              SizedBox(height: h(8)),

              SizedBox(
                height: h(30), // 自我介紹內容可以用較高高度因字數較多
                child: FittedBox(
                  alignment: Alignment.topLeft,
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$selfIntro${selfIntro.isNotEmpty ? '' : '尚未填寫'}',
                    style: const TextStyle(
                      fontSize: 20,
                      color: Colors.black87,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),


        SizedBox(height: h(30)),

        // 標籤 (Wrap 模擬 Figma 的排列)
        Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: tagSpacing / 2),
            child: Container(
              width: maxWrapWidth,
              child: Wrap(
                alignment: WrapAlignment.start,
                spacing: tagSpacing,
                runSpacing: h(8),
                children: [
                  for (int i = 0; i < (tags.length > 6 ? 6 : tags.length); i++)
                    Container(
                      width: tagWidth,
                      height: h(39),
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
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          "  "+tags[i].toString()+"  ",
                          
                          style: const TextStyle(
                            color: Colors.pink,
                            fontWeight: FontWeight.w500,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),


        SizedBox(height: h(60)),

        // 按鈕區 (編輯 / 登出)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SizedBox(
              width: w(156),
              height: h(55),
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const ProfileSetupPage()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromRGBO(255, 200, 202, 1),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                    side: const BorderSide(color: Colors.black, width: 2),
                  ),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '編輯個人資料',
                    style: TextStyle(
                      fontFamily: 'Kiwi Maru',
                      fontWeight: FontWeight.w500,
                      fontSize: 20,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: w(156),
              height: h(55),
              child: ElevatedButton(
                onPressed: _logout,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                    side: const BorderSide(color: Colors.black, width: 2),
                  ),
                ),
                child : FittedBox(
                  fit: BoxFit.scaleDown,
                  child: const Text(
                    '登出',
                    style: TextStyle(
                      color: Color.fromRGBO(246, 157, 158, 1),
                      fontFamily: 'Kiwi Maru',
                      fontWeight: FontWeight.w500,
                      fontSize: 20,
                    ),
                  ),
                ),
                
              ),
            ),
          ],
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
      backgroundColor: Color(0xFCD3F8F3),
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
              child: buildTitleBlock(screenWidth, screenHeight),
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
                child: buildSelfprofileBlock(screenWidth, screenHeight),
              ),
            ),
          ],
        ),
      )
    );
  }
}

extension on User {
  get data => null;
}
