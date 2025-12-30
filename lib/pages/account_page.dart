import 'package:auto_size_text/auto_size_text.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'package:firebase_storage/firebase_storage.dart';
// import 'package:dating_app/profile_setup_page.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import '../main.dart';
import 'package:dating_app/pages/hidden_stories_page.dart';
import 'dart:io';
import 'package:dating_app/constants/data_constants.dart';

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

  // 新增的變數，從 Firebase 讀取
  Set<String> habits = {};
  String? educationLevels;
  String? department;
  bool? matchSameDepartment;
  Set<String> matchGender = {};
  Set<String> matchSchools = {};
  // String height = '';

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

      // 添加 print 來檢查 data 的內容
      print('Firebase data keys: ${data.keys.toList()}');  // 印出所有欄位名稱
      print('matchSameDepartment: ${data['matchSameDepartment']}');

      nameController.text = data['name'] ?? '';
      birthdayController.text = data['birthday'] ?? '';
      bioController.text = data['bio'] ?? '';
      email = data['email'] ?? user.email ?? '';
      photoURL = data['photoUrl']  ?? '';
      tags = List<String>.from(data['tags'] ?? []);
      gender = data['gender'] ?? '';
      genderDetail = data['genderDetail'];
      orientation = data['orientation'] ?? '';
      mbti = data['mbti'];
      zodiac = data['zodiac'];
      school = data['school'] ?? '';
      selfIntro = data['selfIntro'] ?? '';

      // 新增變數的讀取
      habits = Set<String>.from(data['habits'] ?? []);
      educationLevels = data['educationLevels'];
      department = data['department'] ?? '';
      matchSameDepartment = data['matchSameDepartment'];
      matchGender = Set<String>.from(data['matchGender'] ?? []);
      matchSchools = Set<String>.from(data['matchSchools'] ?? []);
      // height = data['height'] ?? '';
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
      // ScaffoldMessenger.of(context).showSnackBar(
      //   const SnackBar(content: Text('個人資料已更新')),
      // );
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


  Future<void> deleteUserAccount(BuildContext context) async {
    final firestore = FirebaseFirestore.instance;
    final auth = FirebaseAuth.instance;
    final currentUser = auth.currentUser;

    if (currentUser == null) return;

    final currentUserId = currentUser.uid;

    try {
      // 確認刪除
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("確認刪除帳號"),
          content: const Text("帳號刪除後將無法恢復，確定要繼續嗎？"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("取消")),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("刪除")),
          ],
        ),
      );

      if (confirm != true) return;

      // 1️⃣ 刪除使用者主資料
      // 🔹 Step 1: 刪除已知子集合（例如 'pushed', 'matches'）
      final userDocRef = firestore.collection('users').doc(currentUserId);
      final subcollectionNames = ['dailyMatches','pushed', 'matches','notices','pushed']; // 根據你的資料結構補齊所有子集合名稱

      for (final name in subcollectionNames) {
        final subcollection = userDocRef.collection(name);
        final docs = await subcollection.get();
        for (final doc in docs.docs) {
          await doc.reference.delete();
        }
      }

      // 🔹 Step 2: 刪除主文件
      await userDocRef.delete();

      // 2️⃣ 刪除所有其他使用者底下的 pushed / matches 中有該使用者的紀錄
      final allUsers = await firestore.collection('users').get();
      for (var userDoc in allUsers.docs) {
        final userId = userDoc.id;
        if (userId == currentUserId) continue;

        // pushed
        final pushedRef = firestore.collection('users').doc(userId).collection('pushed');
        final pushedDocs = await pushedRef.where('userId', isEqualTo: currentUserId).get();
        for (var doc in pushedDocs.docs) {
          await pushedRef.doc(doc.id).delete();
        }

        // matches
        final matchesRef = firestore.collection('users').doc(userId).collection('matches');
        final matchDocs = await matchesRef.where('userId', isEqualTo: currentUserId).get();
        for (var doc in matchDocs.docs) {
          await matchesRef.doc(doc.id).delete();
        }
      }

      // 3️⃣ 刪除 likes 集合中與該使用者有關的紀錄
      final likesRef = firestore.collection('likes');
      final allLikes = await likesRef.get();
      for (var doc in allLikes.docs) {
        if (doc.id.contains(currentUserId)) {
          await likesRef.doc(doc.id).delete();
        }
      }     

      // 4️⃣ 刪除 chats 集合中與該使用者有關的聊天室
      final chatsRef = firestore.collection('chats');
      final allChats = await chatsRef.get();
      for (var chat in allChats.docs) {
       if (chat.id.contains(currentUserId)) {
         final messagesRef = chatsRef.doc(chat.id).collection('messages');

             // 🔹 先刪除 messages 子集合
         final messagesSnapshot = await messagesRef.get();
         for (var msg in messagesSnapshot.docs) {
           await msg.reference.delete();
         }

             // 🔹 再刪除 chat 文件
         await chat.reference.delete();

           //  print("🗑️ 已刪除聊天 ${chat.id} 及其 messages 子集合");
       }
     }

      // 5️⃣ 刪除 Firebase Auth 帳號
      await currentUser.delete();

      // 6️⃣ 導回 WelcomePage
      await FirebaseAuth.instance.signOut();
      await GoogleSignIn().signOut();

      if (context.mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (context) => const WelcomePage()),
          (route) => false,
        );
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("帳號已刪除")),
      );
    } catch (e) {
      debugPrint("❌ 刪除帳號時發生錯誤: $e");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("刪除失敗：$e")),
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
                  /*TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: '名稱'),
                  ),
                  const SizedBox(height: 16),*/
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
    //double pxH(double px) => screenHeight * (px / 917);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          flex: 1,
          child: Image(
            image: AssetImage('assets/qing.png'),
            width: pxW(28),
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
        Flexible(
          flex: 1,
          child: Align(
            alignment: Alignment.centerRight,
            child: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.black),
              onSelected: (value) async {
                if (value == 'hidden') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const HiddenStoriesPage()),
                  );
                } else if (value == 'delete') {
                  // reuse existing delete flow which includes confirmation
                  deleteUserAccount(context);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'hidden', child: Text('查看已隱藏的動態')),
                PopupMenuItem(value: 'delete', child: Text('刪除帳號')),
              ],
            ),
          ),
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

  final AutoSizeGroup myGroup = AutoSizeGroup();
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
                backgroundImage: (photoURL != null && photoURL!.isNotEmpty)
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
                width: w(300),
                 child: AutoSizeText(
                   '學校：$school${school.isNotEmpty ? '' : '尚未填寫'}',
                   maxLines: 1,
                   style: const TextStyle(
                     fontFamily: 'Kiwi Maru',
                     fontWeight: FontWeight.w500,
                     fontSize: 30, // 最大字級
                     color: Colors.black,
                   ),
                   minFontSize: 16, // 最小字級，避免過小
                   overflow: TextOverflow.ellipsis,
                   group: myGroup, // 👈 放進同一個 group
                 ),
              ),

              SizedBox(height: h(8)),

              SizedBox(
                  height: h(30),
                  width: w(300),
                  child: AutoSizeText(
                    '學系：${department!='' ? department : '尚未填寫'}',
                    maxLines: 1,
                    style: const TextStyle(
                      fontFamily: 'Kiwi Maru',
                      fontWeight: FontWeight.w500,
                      fontSize: 30,
                      color: Colors.black,
                    ),
                    minFontSize: 16,
                    overflow: TextOverflow.ellipsis,
                    group: myGroup,
                  ),
                ),

              SizedBox(height: h(8)),
                
              SizedBox(
                height: h(30),
                width: w(300),
                child: AutoSizeText(
                  '性別：$gender${gender.isNotEmpty ? '' : '尚未填寫'}',
                  maxLines: 1,
                  style: const TextStyle(
                    fontFamily: 'Kiwi Maru',
                    fontWeight: FontWeight.w500,
                    fontSize: 30,
                    color: Colors.black,
                  ),
                  minFontSize: 16,
                  overflow: TextOverflow.ellipsis,
                  group: myGroup, // 👈 放進同一個 group
                ),
              ),

              SizedBox(height: h(8)),

              SizedBox(
                height: h(30),
                width: w(300),
                child: AutoSizeText(
                  '自我介紹:',
                  maxLines: 1,
                  style: const TextStyle(
                    fontFamily: 'Kiwi Maru',
                    fontWeight: FontWeight.w500,
                    fontSize: 30,
                    color: Colors.black,
                  ),
                  minFontSize: 16,
                  overflow: TextOverflow.ellipsis,
                  group: myGroup, // 👈 放進同一個 group
                ),
              ),

              SizedBox(height: h(8)),

              SizedBox(
                height: h(100), // 自我介紹內容可以用較高高度因字數較多
                width: w(300),
                child: AutoSizeText(
                  '$selfIntro${selfIntro.isNotEmpty ? '' : '尚未填寫'}',
                  
                  style: const TextStyle(
                      fontSize: 20,
                      color: Colors.black87,
                      fontWeight: FontWeight.w500,
                    ),
                  minFontSize: 16,
                  overflow: TextOverflow.ellipsis,
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
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SimpleProfileEditPage(
                        name: nameController.text,
                        birthday: birthdayController.text,
                        mbti: mbti,
                        zodiac: zodiac,
                        selfIntro: selfIntro,
                        tags: tags,
                        selectedHabits: habits,  // 從 Firebase 讀取
                        selectedMBTI: mbti,
                        selectedZodiac: zodiac,
                        selectededucationLevels: educationLevels,
                        selectedDepartment: department,
                        matchSameDepartment: matchSameDepartment,
                        gender: gender,
                        matchGender: matchGender,
                        matchSchools: matchSchools,
                        // height: height,
                        photoUrl: photoURL,
                        onSave: (data) async {
                          // 寫回 Firebase
                          await FirebaseFirestore.instance.collection('users').doc(user!.uid).update(data);
                          setState(() {
                            // 更新本地變數
                            nameController.text = data['name'] ?? '';
                            birthdayController.text = data['birthday'] ?? '';
                            selfIntro = data['selfIntro'] ?? '';
                            habits = Set<String>.from(data['habits'] ?? []);
                            mbti = data['mbti'];
                            zodiac = data['zodiac'];
                            educationLevels = data['educationLevels'];
                            department = data['department'];
                            matchSameDepartment = data['matchSameDepartment'];
                            gender = data['gender'] ?? '';
                            matchGender = Set<String>.from(data['matchGender'] ?? []);
                            matchSchools = Set<String>.from(data['matchSchools'] ?? []);
                            // height = data['height'] ?? '';
                            photoURL = data['photoUrl'];
                            tags = List<String>.from(data['tags'] ?? []);
                            mbti = data['mbti'];  // 更新 mbti
                            zodiac = data['zodiac'];  // 更新 zodiac
                          });
                        },
                      ),
                    ),
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

class SimpleProfileEditPage extends StatefulWidget {
  final String name;
  final String birthday;
  final String? mbti;
  final String? zodiac;
  final String selfIntro;
  final List<String> tags;
  final Set<String> selectedHabits;
  final String? selectedMBTI;
  final String? selectedZodiac;
  final String? selectededucationLevels;
  final String? selectedDepartment;
  final bool? matchSameDepartment;
  final String gender;
  final Set<String> matchGender;
  final Set<String> matchSchools;
  // final String height;
  final String? photoUrl;
  final ValueChanged<Map<String, dynamic>>? onSave;

  const SimpleProfileEditPage({
    super.key,
    required this.name,
    required this.birthday,
    required this.mbti,
    required this.zodiac,
    required this.selfIntro,
    required this.tags,
    required this.selectedHabits,
    required this.selectedMBTI,
    required this.selectedZodiac,
    required this.selectededucationLevels,
    required this.selectedDepartment,
    required this.matchSameDepartment,
    required this.gender,
    required this.matchGender,
    required this.matchSchools,
    // required this.height,
    required this.photoUrl,
    this.onSave,
  });

  @override
  State<SimpleProfileEditPage> createState() => _SimpleProfileEditPageState();
}

class _SimpleProfileEditPageState extends State<SimpleProfileEditPage> {
  late TextEditingController nameController;
  late TextEditingController birthdayController;
  late TextEditingController selfIntroController;
  // late TextEditingController heightController;
  File? _selectedImage;
  bool _isUploadingPhoto = false;
  String? _photoUrl;

  late Set<String> selectedHabits;
  late String? selectedMBTI;
  late String? selectedZodiac;
  late String? selectededucationLevels;
  late String? selectedDepartment;
  late bool? matchSameDepartment;
  late String gender;
  late Set<String> matchGender;
  late Set<String> matchSchools;
  late List<String> tags;

  final Map<String, bool> isInterestsExpanded = {
    '運動': false,
    '寵物': false,
    '電影': false,
  };

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: widget.name);
    birthdayController = TextEditingController(text: widget.birthday);
    selfIntroController = TextEditingController(text: widget.selfIntro);
    // heightController = TextEditingController(text: widget.height);
    _photoUrl = widget.photoUrl;

    selectedHabits = Set<String>.from(widget.selectedHabits);
    selectedMBTI = widget.selectedMBTI;
    selectedZodiac = widget.selectedZodiac;
    selectededucationLevels = widget.selectededucationLevels;
    selectedDepartment = widget.selectedDepartment;
    matchSameDepartment = widget.matchSameDepartment;
    gender = widget.gender;
    matchGender = Set<String>.from(widget.matchGender);
    matchSchools = Set<String>.from(widget.matchSchools);
    tags = List<String>.from(widget.tags);

    // 根據已選興趣初始化 isInterestsExpanded
    for (final interest in isInterestsExpanded.keys) {
      if (selectedHabits.contains(interest)) {
        isInterestsExpanded[interest] = true;
      }
    }

    print('matchSameDepartment: $matchSameDepartment');

    print('test matchGender:');
    for(final tmp in matchGender) {
      print(tmp);
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    birthdayController.dispose();
    selfIntroController.dispose();
    // heightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('編輯個人資料')),
      body: GestureDetector(
        behavior: HitTestBehavior.opaque, // 讓空白處也能偵測點擊
        onTap: () {
          FocusScope.of(context).requestFocus(FocusNode()); // 明確移除焦點
        },
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 大頭照
              const Text('大頭照'),
              const SizedBox(height: 8),
              Center(  // 新增 Center 來橫向置中大頭照
                child: GestureDetector(
                  onTap: _pickImage,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.blue, width: 2),
                        ),
                        child: CircleAvatar(
                          radius: 50,
                          backgroundImage: _selectedImage != null
                              ? FileImage(_selectedImage!)
                              : (_photoUrl != null ? NetworkImage(_photoUrl!) : null),
                          child: _selectedImage == null && _photoUrl == null
                              ? const Icon(Icons.add_a_photo)
                              : null,
                        ),
                      ),
                      if (_isUploadingPhoto) const CircularProgressIndicator(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              /*// 姓名
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: '姓名'),
              ),
              const SizedBox(height: 16),*/

              // 性別
              const Text('性別'),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: ['男性', '女性'].map((g) => OutlinedButton(
                  onPressed: () => setState(() => gender = g),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: gender == g ? Colors.blue.shade100 : null,
                  ),
                  child: Text(g),
                )).toList(),
              ),
              const SizedBox(height: 16),

              // 要配對的性別
              const Text('要配對的性別'),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: ['男性', '女性'].map((g) => OutlinedButton(
                  onPressed: () {
                    setState(() {
                      if (matchGender.contains(g)) {
                        matchGender.remove(g);
                      } else {
                        matchGender.add(g);
                      }
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    backgroundColor: matchGender.contains(g) ? Colors.blue.shade100 : null,
                  ),
                  child: Text(g),
                )).toList(),
              ),
              const SizedBox(height: 16),

              // 要配對的學校
              const Text('要配對的學校'),
              const SizedBox(height: 8),
              _buildSchoolChoice('國立陽明交通大學', 'NYCU'),
              const SizedBox(height: 8),
              _buildSchoolChoice('國立清華大學', 'NTHU'),
              const SizedBox(height: 16),

              // tags
              const Text('個性化標籤'),
              const SizedBox(height: 8),
              GridView.count(
                crossAxisCount: 4, // 每行4個
                shrinkWrap: true,
                mainAxisSpacing: 12,
                crossAxisSpacing: 16,
                childAspectRatio: 1.7,
                physics: const NeverScrollableScrollPhysics(), // 禁止滾動，由外部控制
                children: tagList.map((tag) {
                  final isSelected = tags.contains(tag);
                  return SizedBox(
                    height: 40,
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          if (isSelected) {
                            tags.remove(tag);
                          } else {
                            tags.add(tag);
                          }
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isSelected ? Colors.blue : Colors.white,
                        foregroundColor: isSelected ? Colors.white : Colors.black,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: isSelected ? Colors.blue : Colors.grey),
                        ),
                      ),
                      child: Text(tag, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // habits (興趣)
              const Text('興趣'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in mainInterests) ...[
                    _buildInterestChip(tag),
                    if (isInterestsExpanded.containsKey(tag))  // 如果點了有子選項的，插入子項按鈕（較小，框起來）
                      if (isInterestsExpanded[tag] == true)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color.fromARGB(51, 224, 201, 119), // 底色
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: interestsSubtags[tag]!.map((sub) {
                              return ChoiceChip(
                                label: Text(sub, style: const TextStyle(fontSize: 13)),
                                selected: selectedHabits.contains(sub),
                                onSelected: (selected) {
                                  setState(() {
                                    selected ? selectedHabits.add(sub) : selectedHabits.remove(sub);
                                  });
                                },
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                              );
                            }).toList(),
                          ),
                        ),
                  ]
                ],
              ),
              const SizedBox(height: 16),

              // mbti
              const Text('MBTI'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: mbtiList.map((type) => ChoiceChip(
                  label: Text(type),
                  selected: selectedMBTI == type,
                  onSelected: (_) {
                      setState(() {
                      if (selectedMBTI == type) {
                        // 再點一次同一個 chip → 取消選取
                        selectedMBTI = null;
                      } else {
                        // 選取新的 chip
                        selectedMBTI = type;
                      }
                    });
                  },
                )).toList(),
              ),
              const SizedBox(height: 16),

              // 星座
              const Text('星座'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: zodiacList.map((sign) => ChoiceChip(
                  label: Text(sign),
                  selected: selectedZodiac == sign,
                  onSelected: (_) => setState(() => selectedZodiac = sign),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                )).toList(),
              ),
              const SizedBox(height: 16),

              // 生日
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
                    birthdayController.text = '${picked.year}/${picked.month.toString().padLeft(2, '0')}/${picked.day.toString().padLeft(2, '0')}';
                  }
                },
                decoration: const InputDecoration(labelText: '生日'),
              ),
              const SizedBox(height: 16),

              // // 身高
              // TextField(
              //   controller: heightController,
              //   keyboardType: TextInputType.number,
              //   decoration: const InputDecoration(labelText: '身高（公分）'),
              // ),
              // const SizedBox(height: 16),

              // 在學狀態
              const Text('在學狀態'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: educationLevelsList.map((status) => ChoiceChip(
                  label: Text(status),
                  selected: selectededucationLevels == status,
                  onSelected: (_) => setState(() => selectededucationLevels = status),
                )).toList(),
              ),
              const SizedBox(height: 16),

              // 系所
              DropdownSearch<String>(
                popupProps: PopupProps.menu(
                  showSearchBox: true, // 啟用搜尋欄
                  searchFieldProps: TextFieldProps(
                    decoration: InputDecoration(
                      hintText: '輸入系所名稱搜尋',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  fit: FlexFit.loose, // 確保選單適應內容
                  constraints: BoxConstraints(maxHeight: 300), // 限制選單高度
                ),
                items: departmentList, // 你的系所列表
                selectedItem: selectedDepartment, // 當前選擇的值
                onChanged: (value) {
                  setState(() {
                    selectedDepartment = value!; // 更新選擇的值
                  });
                },
                dropdownDecoratorProps: DropDownDecoratorProps(
                  dropdownSearchDecoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    hintText: '請選擇系所',
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 是否推薦同系所的人
              const Text('是否推薦同系所的人'),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  OutlinedButton(
                    onPressed: () => setState(() => matchSameDepartment = true),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: matchSameDepartment == true ? Colors.blue.shade100 : null,
                    ),
                    child: const Text('是'),
                  ),
                  OutlinedButton(
                    onPressed: () => setState(() => matchSameDepartment = false),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: matchSameDepartment == false ? Colors.blue.shade100 : null,
                    ),
                    child: const Text('否'),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 自我介紹
              TextField(
                controller: selfIntroController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: '自我介紹'),
              ),
              const SizedBox(height: 32),

              ElevatedButton(
                onPressed: () {
                  widget.onSave?.call({
                    'name': nameController.text.trim(),
                    'birthday': birthdayController.text.trim(),
                    'selfIntro': selfIntroController.text.trim(),
                    'habits': selectedHabits.toList(),
                    'mbti': selectedMBTI,
                    'zodiac': selectedZodiac,
                    'educationLevels': selectededucationLevels,
                    'department': selectedDepartment,
                    'matchSameDepartment': matchSameDepartment,
                    'gender': gender,
                    'matchGender': matchGender.toList(),
                    'matchSchools': matchSchools.toList(),
                    // 'height': heightController.text.trim(),
                    'photoUrl': _photoUrl,
                    'tags': tags,
                  });
                  Navigator.pop(context);
                },
                child: const Text('儲存'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInterestChip(String tag) {
    final selected = selectedHabits.contains(tag);
    return ChoiceChip(
      label: Text(tag),
      selected: selected,
      onSelected: (selected) {
        setState(() {
          selected ? selectedHabits.add(tag) : selectedHabits.remove(tag);
          if (isInterestsExpanded.containsKey(tag)) {
            isInterestsExpanded[tag] = !isInterestsExpanded[tag]!;
            if (!selected) {
              for(final subtag in interestsSubtags[tag] ?? []) {
                if (selectedHabits.contains(subtag)) {
                  selectedHabits.remove(subtag);
                }
              }
            }
          }
        });
      },
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
    );
  }

  Widget _buildSchoolChoice(String label, String code) {
    final isSelected = matchSchools.contains(code);
    return ElevatedButton(
      onPressed: () {
        setState(() {
          if (isSelected) {
            matchSchools.remove(code);
          } else {
            matchSchools.add(code);
          }
        });
      },
      style: ElevatedButton.styleFrom(
        backgroundColor: isSelected ? Colors.blue.shade100 : Colors.white,
      ),
      child: Text(label),
    );
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    setState(() {
      _selectedImage = File(pickedFile.path);
      _isUploadingPhoto = true;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final ref = FirebaseStorage.instance.ref().child('user_photos').child('${user.uid}.jpg');
      await ref.putFile(_selectedImage!);
      final url = await ref.getDownloadURL();

      setState(() {
        _photoUrl = url;
        _isUploadingPhoto = false;
      });
    } catch (e) {
      setState(() => _isUploadingPhoto = false);
    }
  }
}

extension on User {
  get data => null;
}
