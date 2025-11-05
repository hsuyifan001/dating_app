import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'home_page.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:dropdown_search/dropdown_search.dart';
import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'services/fcm_service.dart'; // 新增 import
import 'package:dating_app/constants/data_constants.dart';

class ProfileSetupPage extends StatefulWidget {

  const ProfileSetupPage({super.key});

  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

// 自訂 TextInputFormatter，根據字元寬度限制輸入
class WidthLimitingTextInputFormatter extends TextInputFormatter {
  final double maxWidth; // 最大寬度（像素）
  final double chineseCharWidth; // 中文字寬度
  final double numberWidth; // 數字寬度
  final double letterWidth; // 英文字平均寬度
  final double spaceWidth; // 空格寬度
  final VoidCallback? onWidthExceeded; // 超過寬度時的回調
  Timer? _debounceTimer; // 防抖計時器

  WidthLimitingTextInputFormatter({
    required this.maxWidth,
    this.chineseCharWidth = 20.0,
    this.numberWidth = 10.9,
    this.letterWidth = 12.0,
    this.spaceWidth = 8.0,
    this.onWidthExceeded,
  });

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    double totalWidth = _calculateWidth(newValue.text);
    if (totalWidth > maxWidth) {
      // 超過寬度，觸發回調並保持舊值
      if (_debounceTimer?.isActive ?? false) {
        _debounceTimer!.cancel();
      }
      _debounceTimer = Timer(const Duration(milliseconds: 500), () {
        onWidthExceeded?.call();
      });
      return oldValue;
    }
    _debounceTimer?.cancel(); // 取消防抖計時器
    return newValue; // 允許輸入
  }

  double _calculateWidth(String text) {
    double totalWidth = 0.0;
    for (var char in text.runes) {
      String charStr = String.fromCharCode(char);
      if (RegExp(r'[\u4e00-\u9fa5]').hasMatch(charStr)) {
        totalWidth += chineseCharWidth; // 中文字
      } else if (RegExp(r'[0-9]').hasMatch(charStr)) {
        totalWidth += numberWidth; // 數字
      } else if (RegExp(r'[a-zA-Z]').hasMatch(charStr)) {
        totalWidth += letterWidth; // 英文
      } else if (charStr == ' ') {
        totalWidth += spaceWidth; // 空格
      }
    }
    return totalWidth;
  }
}

class _ProfileSetupPageState extends State<ProfileSetupPage> with SingleTickerProviderStateMixin {
  File? _selectedImage;

  final PageController _pageController = PageController();
  int _currentPage = 0;

  final nameController = TextEditingController();
  final birthdayController = TextEditingController();
  // final heightController = TextEditingController();
  
  String? gender;
  Set<String> matchgender = {};
  String? genderDetail; // 記得刪掉
  //String? orientation;
  final TextEditingController selfIntroController = TextEditingController();

  Set<String> selectedTags = {};
  Set<String> selectedHabits = {};
  String? selectedMBTI;
  String? selectedZodiac;
  String? selectededucationLevels;
  String? selectedDepartment;
  String? _photoUrl;
  bool _isUploadingPhoto = false;
  Set<String> matchSchools = {};
  bool? matchSameDepartment;
  final FocusNode _nameFocusNode = FocusNode(); // 添加 FocusNode

  final TextEditingController customSportController = TextEditingController();
  final TextEditingController customPetController = TextEditingController();

  final isInterestsExpanded = {
    '運動': false,
    '寵物': false,
    '電影': false,
  };

  void showAutoDismissDialog(String message) {
    FocusScope.of(context).unfocus();
    print('顯示提示: $message');
    // 在顯示新 Dialog 前關閉舊 Dialog
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    showGeneralDialog(
      context: context,
      barrierDismissible: true, // 允許點擊背景，但避免立即關閉
      barrierLabel: '', // 避免無障礙標籤問題
      barrierColor: Colors.transparent, // 透明背景
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        });
        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              margin: const EdgeInsets.symmetric(horizontal: 32),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                message,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
          child: child,
        );
      },
    );
    FocusScope.of(context).unfocus();
  }

  void _nextPage() async {
    // 確保所有輸入欄位失去焦點
    FocusScope.of(context).requestFocus(FocusNode());
    
    if (_currentPage == 0) {
      final name = nameController.text.trim();
      if (_selectedImage == null && _photoUrl == null) {
        showAutoDismissDialog('請上傳照片');
        return;
      }
      if (name.isEmpty) {
        showAutoDismissDialog('請輸入名字');
        return;
      }
      if (gender == null) {
        showAutoDismissDialog('請選擇性別');
        return;
      }
      if (matchgender.isEmpty) {
        showAutoDismissDialog('請選擇想要配對的性別');
        return;
      }

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text('哈囉，$name!'),
          content: const Text('確認使用此名稱嗎？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('編輯名稱')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('確定使用此名稱')),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    else if (_currentPage == 1) {
      if (matchSchools.isEmpty) {
        showAutoDismissDialog('請至少選擇一所學校');
        return;
      }
    }
    else if (_currentPage == 2) {
      if (selectedTags.isEmpty) {
        showAutoDismissDialog('請至少選擇一個標籤');
        return;
      }
    }
    else if (_currentPage == 3) {
      if (selectedHabits.isEmpty) {
        showAutoDismissDialog('請至少選擇一個興趣');
        return;
      }
      if (selectedMBTI == null) {
        showAutoDismissDialog('請選擇 MBTI');
        return;
      }
      if (selectedZodiac == null) {
        showAutoDismissDialog('請選擇星座');
        return;
      }
      if (birthdayController.text.trim().isEmpty) {
        showAutoDismissDialog('請輸入生日');
        return;
      }
      // if (heightController.text.trim().isEmpty) {
      //   showAutoDismissDialog('請輸入身高');
      //   return;
      // }
      if (selectededucationLevels == null) {
        showAutoDismissDialog('請選擇在學狀態');
        return;
      }
      if (selectedDepartment == null) {
        showAutoDismissDialog('請選擇科系');
        return;
      }
      if (matchSameDepartment == null) {
        showAutoDismissDialog('請選擇是否與同系配對');
        return;
      }
      if (selfIntroController.text.trim().isEmpty) {
        showAutoDismissDialog('請輸入自我介紹');
        return;
      }
    }

    if (_currentPage < 3) {
      setState(() => _currentPage++);
      await _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      // FocusScope.of(context).unfocus(); // 換頁的時候關鍵盤(避免更改到前一頁的內容)
      FocusScope.of(context).requestFocus(FocusNode()); // 確保換頁後無焦點
    } else {
      _submit();
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      setState(() => _currentPage--);
      _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      FocusScope.of(context).requestFocus(FocusNode()); // 確保換頁後無焦點
    }
  }

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    String school = '';
    final email = user.email ?? '';
    if (email.endsWith('@g.nycu.edu.tw') || email.endsWith('@nycu.edu.tw')) {
      school = 'NYCU';
    } else if (email.endsWith('@gapp.nthu.edu.tw') || email.endsWith('@nthu.edu.tw')) {
      school = 'NTHU';
    } else {
      school = '其他';
    }

    final profileData = {
      'name': nameController.text.trim(),
      'matchSchools': matchSchools.toList(),
      'gender': gender,
      'matchGender': matchgender.toList(),
      'tags': selectedTags.toList(),
      'habits': selectedHabits.toList(),
      'mbti': selectedMBTI,
      'zodiac': selectedZodiac,
      'birthday': birthdayController.text.trim(),
      // 'height': heightController.text.trim(),
      'educationLevels': selectededucationLevels,
      'department': selectedDepartment,
      'matchSameDepartment': matchSameDepartment,
      'school': school,
      'email': user.email,
      'photoUrl': _photoUrl, // ✅ 加這行
      'selfIntro': selfIntroController.text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
      // 'fcmToken': await FirebaseMessaging.instance.getToken(),
    };
    
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set(profileData);

    // 改為：若之前有暫存的 FCM token，完成個人資料後再寫入
    try {
      await FcmService.saveTokenIfUserProfileExists(user.uid);
      print('嘗試將 pending FCM token 寫入 Firestore');
    } catch (e) {
      print('寫入 pending FCM token 失敗: $e');
    }

    // 新增：生成初始配對
    await _generateInitialMatches(user.uid);

    if (context.mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage()));
    }
  }

  // 新增方法：生成初始配對
  Future<void> _generateInitialMatches(String userId) async {
    try {
      // 直接查詢所有用戶（限制 100 個）
      final snapshot = await FirebaseFirestore.instance.collection('users').limit(100).get();
      final allUsers = snapshot.docs.where((doc) => doc.id != userId).toList();

      // 隨機打亂並選擇前 25 個
      allUsers.shuffle();
      final selectedCandidates = allUsers.take(25).toList();

      // 儲存到 dailyMatches
      final matchDocRef = FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('dailyMatches')
        .doc(DateTime.now().toIso8601String().substring(0, 10).replaceAll('-', ''));

      await matchDocRef.set({
        'createdAt': FieldValue.serverTimestamp(),
        'userIds': selectedCandidates.map((doc) => doc.id).toList(),
        'currentMatchIdx': 0,
      });

      print('初始配對已生成，共 ${selectedCandidates.length} 個用戶');
    } catch (e) {
      print('生成初始配對失敗: $e');
    }
  }

  Future<void> _loadUserData() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
  if (doc.exists) {
    final data = doc.data()!;
    setState(() {
      // 基本文字輸入
      nameController.text = data['name'] ?? '';
      birthdayController.text = data['birthday'] ?? '';
      // heightController.text = data['height'] ?? '';
      selfIntroController.text = data['selfIntro'] ?? '';

      // 單選
      gender = data['gender'];
      //orientation = data['orientation'];
      selectedMBTI = data['mbti'];
      selectedZodiac = data['zodiac'];
      selectededucationLevels = data['educationLevels'];
      selectedDepartment = data['department'];

      // 多選
      matchgender = Set<String>.from(data['matchGender'] ?? []);
      selectedTags = Set<String>.from(data['tags'] ?? []);
      selectedHabits = Set<String>.from(data['habits'] ?? []);
      matchSchools = Set<String>.from(data['matchSchools'] ?? []);

      // 布林
      matchSameDepartment = data['matchSameDepartment'];

      // 照片
      _photoUrl = data['photoUrl'];
    });
  }
}

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }
  @override
  void dispose() {
    _pageController.dispose();
    nameController.dispose();
    birthdayController.dispose();
    selfIntroController.dispose();
    customSportController.dispose();
    customPetController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 背景圖片對應表
    final backgroundMap = {
      0: 'assets/profile_setup_background.png',
      1: 'assets/school_page_background.png',
      2: 'assets/tags_background.png',
    };

    final bg = backgroundMap[_currentPage];

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: BoxDecoration(
          // 根據頁面決定背景顏色或漸層
          color: _currentPage == 0 ? const Color(0xFCD3F8F3) :
                 _currentPage == 1 ? const Color(0xFFF6F4F2) :
                 _currentPage == 2 ? const Color(0xFFD3F8F3FC) : null, // 若是漸層則不能同時設 color
        ),
        child: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (bg != null)
                Image.asset(
                  bg,
                  fit: BoxFit.cover,
                ),
              Container(
                // color: const Color.fromARGB(255, 51, 51, 51).withOpacity(0.05),
                color: Colors.black.withOpacity(0.05),
              ),
              Column(
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque, // 讓空白處也能偵測點擊
                      onTap: () {
                        FocusScope.of(context).requestFocus(FocusNode()); // 明確移除焦點
                      },
                      child: PageView(
                        controller: _pageController,
                        physics: const NeverScrollableScrollPhysics(),
                        children: [
                          // _buildNamePage(),
                          _buildBasicInfoPage(),
                          _buildMatchSchoolPage(),
                          _buildTagsPage(),
                          // _buildPhotoUploadPage(),
                          // _buildBirthdayPage(),
                          // _buildGenderPage(),
                          // _buildOrientationPage(),
                          _buildHabitsPage(),
                          // _buildManyTagPage(),
                        ],
                      ),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: _currentPage == 0 ? MainAxisAlignment.end : MainAxisAlignment.spaceBetween,
                    children: [
                      if (_currentPage > 0)
                        ElevatedButton(onPressed: _prevPage, child: const Text('上一步')),
                      ElevatedButton(
                        onPressed: _nextPage,
                        child: Text(_currentPage == 3 ? '完成' : '下一步'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMatchSchoolPage() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Container(
        //   color: Colors.black.withOpacity(0.05),
        // ),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  children: [
                    Text(
                      '選擇想要配對的學校',
                      style: TextStyle(
                        fontFamily: 'Kiwi Maru',
                        fontWeight: FontWeight.w400,
                        fontSize: 25,
                        height: 1.0,
                        letterSpacing: 0.0,
                        foreground: Paint()
                          ..style = PaintingStyle.stroke
                          ..strokeWidth = 4
                          ..color = Colors.white,
                      ),
                    ),
                    Text(
                      '選擇想要配對的學校',
                      style: TextStyle(
                        fontFamily: 'Kiwi Maru',
                        fontWeight: FontWeight.w400,
                        fontSize: 25,
                        height: 1.0,
                        letterSpacing: 0.0,
                        color: Color(0xFF5A4A3C),
                        shadows: [
                          Shadow(
                            offset: Offset(2, 2),
                            blurRadius: 2,
                            color: Color(0x80000000),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                Stack(
                  children: [
                    Text(
                      '（可複選）',
                      style: TextStyle(
                        fontFamily: 'Kiwi Maru',
                        fontWeight: FontWeight.w400,
                        fontSize: 25,
                        height: 1.0,
                        letterSpacing: 0.0,
                        foreground: Paint()
                          ..style = PaintingStyle.stroke
                          ..strokeWidth = 4
                          ..color = Colors.white,
                      ),
                    ),
                    Text(
                      '（可複選）',
                      style: TextStyle(
                        fontFamily: 'Kiwi Maru',
                        fontWeight: FontWeight.w400,
                        fontSize: 25,
                        height: 1.0,
                        letterSpacing: 0.0,
                        color: Color(0xFF5A4A3C),
                        shadows: [
                          Shadow(
                            offset: Offset(2, 2),
                            blurRadius: 2,
                            color: Color(0x80000000),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 48),
                _buildSchoolChoice('國立陽明交通大學', 'NYCU'),
                const SizedBox(height: 20),
                _buildSchoolChoice('國立清華大學', 'NTHU'),
                const SizedBox(height: 40),
              
              ],
            ),
          ),
        ),
      ],
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
        side: BorderSide(
          color: isSelected ? Colors.orange : Color(0xFF89C9C2),
          width: 3,
        ),
        backgroundColor: isSelected ? Colors.orange.shade100 : Color(0xFFFEECEC),
        foregroundColor: Color(0xFF5A4A3C),
        minimumSize: const Size(double.infinity, 60),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (isSelected)
            const Icon(Icons.check_circle, color: Colors.orange),
          if (isSelected) const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Kiwi Maru',
              fontWeight: FontWeight.w400,
              fontSize: 18,
              height: 1.0,
              letterSpacing: 0.0,
              color: Color(0xFF5A4A3C),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBasicInfoPage() => SingleChildScrollView(
    // reverse: true, // 讓畫面滑動到輸入欄位
    // padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(height: 120),
        GestureDetector(
          onTap: _pickImage,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 200, // 直徑 = 2 * radius
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Color(0xFF1B578B), width: 4), // 深藍邊框
                ),
                child: CircleAvatar(
                  radius: 100,
                  backgroundImage: _selectedImage != null ? FileImage(_selectedImage!) // 本地剛選的照片
                              : (_photoUrl != null && _photoUrl!.isNotEmpty
                              ? NetworkImage(_photoUrl!) // Firebase 已存的照片
                              : null),
                  child: _selectedImage == null && (_photoUrl == null || _photoUrl!.isEmpty)
                      ? const Text('選擇要上傳的照片')
                      : null,
                ),
              ),
              if (_isUploadingPhoto)
                const CircularProgressIndicator(),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '1. 別人要怎麼稱呼尼？',
          style: TextStyle(
            color: Color(0xFF1B578B),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.center,
          child: SizedBox(
            width: 280, // 控制寬度
            child: TextField(
              focusNode: _nameFocusNode,
              autofocus: false,
              controller: nameController,
              textAlign: TextAlign.center,
              maxLines: 1, // 禁止換行
              inputFormatters: [
                WidthLimitingTextInputFormatter(
                  maxWidth: 10.0, // 約 5 個中文字的寬度
                  chineseCharWidth: 2.0,
                  numberWidth: 1.0,
                  letterWidth: 1.0,
                  spaceWidth: 8.0,
                  onWidthExceeded: () => showAutoDismissDialog('名字最多5個中文字\n數字、英文視作半個中文字'),
                ),
                FilteringTextInputFormatter.allow(
                  RegExp(r'[a-zA-Z0-9\u4e00-\u9fa5 ]'), // 允許中英文、數字、空格
                ),
                FilteringTextInputFormatter.deny(RegExp(r'\n')), // 禁止換行
              ],
              decoration: InputDecoration(
                hintText: '輸入名字',
                contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 0),
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(40),
                  borderSide: const BorderSide(color: Colors.grey),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(40),
                  borderSide: const BorderSide(color: Color(0xFF89C9C2), width: 3),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(40),
                  borderSide: const BorderSide(color: Color(0xFF1B578B), width: 3),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '2. 選擇尼的生理性別',
          style: TextStyle(
            color: const Color(0xFF1B578B),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          // crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ...['男性', '女性'].map((g) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: OutlinedButton(
                onPressed: () => setState(() {
                  gender = g;
                }),
                style: OutlinedButton.styleFrom(
                  backgroundColor: gender == g ? const Color.fromARGB(255, 142, 195, 241) : null,
                  minimumSize: Size(120, 50),
                  side: BorderSide(
                    color: gender == g ? const Color(0xFF1B578B) : Color(0xFF89C9C2),
                    width: 3,
                  ),
                ),
                child: Text(g),
              ),
            )).toList(),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          '3. 選擇想配對的生理性別',
          style: TextStyle(
            color: const Color(0xFF1B578B),
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          // crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ...['男性', '女性'].map((g) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: OutlinedButton(
                onPressed: () => setState(() {
                  if (matchgender.contains(g)) {
                    matchgender.remove(g);
                  } else {
                    matchgender.add(g);
                  }
                }),
                style: OutlinedButton.styleFrom(
                  backgroundColor: matchgender.contains(g) ? const Color.fromARGB(255, 142, 195, 241) : null,
                  minimumSize: Size(120, 50),
                  side: BorderSide(
                    color: matchgender.contains(g) ? const Color(0xFF1B578B) : Color(0xFF89C9C2),
                    width: 3,
                  ),
                ),
                child: Text(g),
              ),
            )).toList(),
          ],
        ),
        // const SizedBox(height: 90),
      ],
    ),
  );

  Widget _buildTagsPage() => Center(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 120),
          const Text(
            '選擇個性化標籤',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: GridView.count(
              crossAxisCount: 4, // 每行4個
              shrinkWrap: true,
              mainAxisSpacing: 12,
              crossAxisSpacing: 16,
              childAspectRatio: 1.7,
              physics: const NeverScrollableScrollPhysics(), // 禁止滾動，由外部控制
              children: tagList.map((tag) {
                final isSelected = selectedTags.contains(tag);
                return SizedBox(
                  height: 40,
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        if (isSelected) {
                          selectedTags.remove(tag);
                        } else {
                          selectedTags.add(tag);
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
          ),
          const SizedBox(height: 32),
        ],
      ),
    ),

  );

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
      if (user == null) {
        throw Exception('使用者未登入');
      }
  
      // 1️⃣ 壓縮圖片
      final Uint8List? compressedImage = await FlutterImageCompress.compressWithFile(
        _selectedImage!.path,
        minWidth: 800, // 降低解析度
        minHeight: 800,
        quality: 70,   // 壓縮品質 0-100
        format: CompressFormat.jpeg,
      );
  
      if (compressedImage == null) {
        throw Exception('壓縮圖片失敗');
      }
  
      // 2️⃣ 上傳壓縮後的檔案
      final ref = FirebaseStorage.instance
          .ref()
          .child('user_photos')
          .child('${user.uid}.jpg');
  
      await ref.putData(
        compressedImage,
        SettableMetadata(contentType: 'image/jpeg'),
      );
  
      // 3️⃣ 取得下載連結
      final url = await ref.getDownloadURL();
  
      setState(() {
        _photoUrl = url;
        _isUploadingPhoto = false;
      });
  
    } catch (e) {
      setState(() => _isUploadingPhoto = false);
    }
  }

  Widget _buildHabitsPage() => SingleChildScrollView(
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('興趣與標籤', style: TextStyle(fontSize: 20)),
        const SizedBox(height: 16),
        const Text('興趣'),
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

        const SizedBox(height: 24),
        const Text('MBTI'),
        const SizedBox(height: 8),
        for(int i = 0; i < 4; i++)
          Wrap(
            spacing: 8,
            children: [
              for(int j = 0; j < 4; j++)
                ChoiceChip(
                  label: Text('${mbtiList[i * 4 + j]}'),
                  selected: selectedMBTI == mbtiList[i * 4 + j],
                  onSelected: (_) => setState(() => selectedMBTI = mbtiList[i * 4 + j]),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
            ]
          ),

        const SizedBox(height: 24),
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
        
        const SizedBox(height: 24),
        const Text('生日'),
        const SizedBox(height: 8),
        TextField(
          controller: birthdayController,
          readOnly: true,
          onTap: () async {
            final now = DateTime.now();
            final picked = await showDatePicker(
              context: context,
              initialDate: DateTime(now.year - 20),
              firstDate: DateTime(1900),
              lastDate: now,
            );
            if (picked != null) {
              birthdayController.text = "${picked.year}/${picked.month.toString().padLeft(2, '0')}/${picked.day.toString().padLeft(2, '0')}";
            }
          },
          decoration: const InputDecoration(hintText: '請選擇生日'),
        ),

        // const SizedBox(height: 24),
        // const Text('身高'),
        // const SizedBox(height: 8),
        // TextField(
        //   controller: heightController,
        //   textAlign: TextAlign.center,
        //   keyboardType: TextInputType.number,
        //   decoration: InputDecoration(
        //     hintText: '請輸入你的身高（公分）',
        //     border: OutlineInputBorder(
        //       borderRadius: BorderRadius.circular(12),
        //     ),
        //     filled: true,
        //     fillColor: Colors.grey[100],
        //   ),
        // ),

        const SizedBox(height: 24),
        const Text('在學狀態'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: educationLevelsList.map((status) => ChoiceChip(
            label: Text(status),
            selected: selectededucationLevels == status,
            onSelected: (selected) {
              setState(() {
                if (selected) {
                  selectededucationLevels = status;
                } else {
                  selectededucationLevels = null;
                }
              });
            },
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          )).toList(),
        ),

        const SizedBox(height: 24),
        const Text('系所'),
        const SizedBox(height: 8),
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

        const SizedBox(height: 24),
        const Text('是否推薦同系所的人'),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            OutlinedButton(
              onPressed: () => setState(() => matchSameDepartment = true),
              style: OutlinedButton.styleFrom(
                backgroundColor: matchSameDepartment == true ? Colors.orange.shade100 : null,
                side: BorderSide(
                  color: matchSameDepartment == true ? Colors.orange : Color(0xFF89C9C2),
                  width: 3,
                ),
              ),
              child: const Text('是'),
            ),
            OutlinedButton(
              onPressed: () => setState(() => matchSameDepartment = false),
              style: OutlinedButton.styleFrom(
                backgroundColor: matchSameDepartment == false ? Colors.orange.shade100 : null,
                side: BorderSide(
                  color: matchSameDepartment == false ? Colors.orange : Color(0xFF89C9C2),
                  width: 3,
                ),
              ),
              child: const Text('否'),
            ),
          ],
        ),

        const SizedBox(height: 24),
        const Text('自我介紹'),
        const SizedBox(height: 8),
        TextField(
          controller: selfIntroController,
          maxLines: null,
          maxLength: 200,
          decoration: InputDecoration(
            hintText: '簡單介紹一下你自己（最多200字）',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
            fillColor: Colors.grey[100],
          ),
        ),
      ],
    ),
  );

  // 分出來的興趣按鈕建構器
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


  // Widget _buildPhotoUploadPage() => Padding(
  //   padding: const EdgeInsets.all(24),
  //   child: Column(
  //     children: [
  //       const Text('上傳你的照片', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
  //       const SizedBox(height: 16),
  //       GestureDetector(
  //         onTap: _pickImage,
  //         child: Stack(
  //           alignment: Alignment.center,
  //           children: [
  //             CircleAvatar(
  //               radius: 80,
  //               backgroundImage: _selectedImage != null ? FileImage(_selectedImage!) : null,
  //               child: _selectedImage == null ? const Icon(Icons.add_a_photo, size: 40) : null,
  //             ),
  //             if (_isUploadingPhoto)
  //               const CircularProgressIndicator(),
  //           ],
  //         ),
  //       ),
  //       const SizedBox(height: 16),
  //       Text(
  //         _photoUrl != null ? '已上傳照片 ✅' : '這將成為你的主照片',
  //         style: TextStyle(color: _photoUrl != null ? Colors.green : Colors.black),
  //       ),
  //     ],
  //   ),
  // );

  // Widget _buildNamePage() => _buildInputPage(
  //       title: '姓名',
  //       controller: nameController,
  //       hint: '請輸入你的名字',
  //       subtitle: '此名稱日後便無法更改',
  //     );

  // Widget _buildBirthdayPage() => Padding(
  //       padding: const EdgeInsets.all(24),
  //       child: Column(
  //         crossAxisAlignment: CrossAxisAlignment.start,
  //         children: [
  //           const Text('生日', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
  //           const SizedBox(height: 24),
  //           TextField(
  //             controller: birthdayController,
  //             readOnly: true,
  //             onTap: () async {
  //               final now = DateTime.now();
  //               final picked = await showDatePicker(
  //                 context: context,
  //                 initialDate: DateTime(now.year - 20),
  //                 firstDate: DateTime(1900),
  //                 lastDate: now,
  //               );
  //               if (picked != null) {
  //                 birthdayController.text = "${picked.year}/${picked.month.toString().padLeft(2, '0')}/${picked.day.toString().padLeft(2, '0')}";
  //               }
  //             },
  //             decoration: const InputDecoration(hintText: '請選擇生日'),
  //           ),
  //         ],
  //       ),
  //     );

  // Widget _buildGenderPage() {
  //   final isDiverse = gender == '多元性別';
  //   final diverseOptions = ['性別一', '性別二', '性別三'];

  //   return Padding(
  //     padding: const EdgeInsets.all(24),
  //     child: Column(
  //       crossAxisAlignment: CrossAxisAlignment.stretch,
  //       children: [
  //         const Text('性別', style: TextStyle(fontSize: 20)),
  //         const SizedBox(height: 12),
  //         for (final g in ['男性', '女性', '多元性別'])
  //           Padding(
  //             padding: const EdgeInsets.symmetric(vertical: 4),
  //             child: OutlinedButton(
  //               onPressed: () => setState(() {
  //                 gender = g;
  //                 genderDetail = null;
  //               }),
  //               style: OutlinedButton.styleFrom(
  //                 backgroundColor: gender == g ? Colors.pink.shade100 : null,
  //                 minimumSize: Size(120, 50),
  //               ),
  //               child: Text(g),
  //             ),
  //           ),
  //         if (isDiverse)
  //           Container(
  //             margin: const EdgeInsets.only(top: 12),
  //             padding: const EdgeInsets.all(8),
  //             decoration: BoxDecoration(
  //               color: Colors.grey.shade200,
  //               borderRadius: BorderRadius.circular(8),
  //             ),
  //             child: Wrap(
  //               spacing: 8,
  //               children: diverseOptions.map((opt) => ChoiceChip(
  //                 label: Text(opt),
  //                 selected: genderDetail == opt,
  //                 onSelected: (_) => setState(() => genderDetail = opt),
  //               )).toList(),
  //             ),
  //           ),
  //       ],
  //     ),
  //   );
  // }

  // Widget _buildOrientationPage() => Padding(
  //       padding: const EdgeInsets.all(24),
  //       child: Column(
  //         crossAxisAlignment: CrossAxisAlignment.stretch,
  //         children: [
  //           const Text('性向', style: TextStyle(fontSize: 20)),
  //           const SizedBox(height: 12),
  //           for (final o in ['異性戀', '同性戀', '雙性戀', '無性戀', '摸索中', '未列出'])
  //             Padding(
  //               padding: const EdgeInsets.symmetric(vertical: 4),
  //               child: OutlinedButton(
  //                 onPressed: () => setState(() => orientation = o),
  //                 style: OutlinedButton.styleFrom(
  //                   backgroundColor: orientation == o ? Colors.pink.shade100 : null,
  //                   minimumSize: Size(120, 50),
  //                 ),
  //                 child: Text(o),
  //               ),
  //             ),
  //           if (orientation == '未列出')
  //             TextField(
  //               controller: otherOrientationController,
  //               decoration: const InputDecoration(hintText: '請輸入你的性向'),
  //             ),
  //         ],
  //       ),
  //     );

  // Widget _buildManyTagPage() => SafeArea(
  //       child: Padding(
  //         padding: const EdgeInsets.all(24),
  //         child: Column(
  //           crossAxisAlignment: CrossAxisAlignment.start,
  //           children: [
  //             Center(
  //               child: Stack(
  //                 children: [
  //                   Text(
  //                     '選擇個性化標籤',
  //                     style: TextStyle(
  //                       fontSize: 36,
  //                       fontWeight: FontWeight.bold,
  //                       foreground: Paint()
  //                         ..style = PaintingStyle.stroke
  //                         ..strokeWidth = 10
  //                         ..color = Colors.white,
  //                     ),
  //                   ),
  //                   const Text(
  //                     '選擇個性化標籤',
  //                     style: TextStyle(
  //                       fontSize: 36,
  //                       fontWeight: FontWeight.bold,
  //                       color: Color(0xFF5A4A3C),
  //                       shadows: [
  //                         Shadow(
  //                           offset: Offset(2, 2),
  //                           blurRadius: 2,
  //                           color: Color(0x80000000),
  //                         ),
  //                       ],
  //                     ),
  //                   ),
  //                 ],
  //               ),
  //             ),
  //             const SizedBox(height: 24),
  //             Expanded(
  //               child: ListView(
  //                 children: allTags.map(_buildArrowTag).toList(),
  //               ),
  //             ),
  //           ],
  //         ),
  //       ),
  //     );

  // Future<void> _saveProfile() async {
  //   final user = FirebaseAuth.instance.currentUser;
  //   if (user == null) return;

  //   if (selectedTags.isEmpty) {
  //     ScaffoldMessenger.of(context).showSnackBar(
  //       const SnackBar(content: Text('請至少選擇一個標籤')),
  //     );
  //     return;
  //   }

  //   await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
  //     'tags': selectedTags.toList(),
  //     'email': user.email,
  //     'school': widget.school,
  //     'createdAt': FieldValue.serverTimestamp(),
  //   });

  //   if (context.mounted) {
  //     Navigator.pushReplacement(
  //       context,
  //       MaterialPageRoute(builder: (context) => const HomePage()),
  //     );
  //   }
  // }

  // Widget _buildInputPage({
  //   required String title,
  //   required TextEditingController controller,
  //   String? hint,
  //   String? subtitle,
  // }) =>
  //     Padding(
  //       padding: const EdgeInsets.all(24),
  //       child: Column(
  //         crossAxisAlignment: CrossAxisAlignment.start,
  //         children: [
  //           Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
  //           const SizedBox(height: 24),
  //           TextField(
  //             controller: controller,
  //             decoration: InputDecoration(hintText: hint),
  //           ),
  //           if (subtitle != null) ...[
  //             const SizedBox(height: 4),
  //             Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
  //           ],
  //         ],
  //       ),
  //     );
  
  // Widget _buildArrowTag(String tag) {
  //   final isSelected = selectedTags.contains(tag);
  //   final description = tagDescriptions[tag] ?? '';

  //   return GestureDetector(
  //     onTap: () {
  //       setState(() {
  //         if (isSelected) {
  //           selectedTags.remove(tag);
  //         } else {
  //           selectedTags.add(tag);
  //         }
  //       });
  //     },
  //     child: Padding(
  //       padding: const EdgeInsets.symmetric(vertical: 6),
  //       child: Row(
  //         crossAxisAlignment: CrossAxisAlignment.center,
  //         children: [
  //           Expanded(
  //             child: Row(
  //               mainAxisAlignment: MainAxisAlignment.center,
  //               children: [
  //                 // Add shadow using PhysicalModel for the tag arrow
  //                 PhysicalModel(
  //                   color: Colors.transparent,
  //                   elevation: 6,
  //                   shadowColor: Colors.black45,
  //                   borderRadius: BorderRadius.circular(8),
  //                   child: CustomPaint(
  //                     painter: _ArrowBorderPainter(
  //                       borderColor: const Color(0xFF9F806C),
  //                       borderWidth: 2,
  //                       clipper: LeftArrowClipper(),
  //                     ),
  //                     child: ClipPath(
  //                       clipper: LeftArrowClipper(),
  //                       child: Container(
  //                         width: 82,
  //                         height: 35,
  //                         color: isSelected
  //                             ? Colors.pink.shade300
  //                             : const Color(0xFFB4F5EE),
  //                         alignment: Alignment.center,
  //                         child: Text(
  //                           tag,
  //                           style: TextStyle(
  //                             color: isSelected ? Colors.white : Colors.black87,
  //                             fontWeight: FontWeight.w600,
  //                             shadows: [
  //                               Shadow(
  //                                 color: Colors.black26,
  //                                 offset: Offset(1, 2),
  //                                 blurRadius: 4,
  //                               ),
  //                             ],
  //                           ),
  //                         ),
  //                       ),
  //                     ),
  //                   ),
  //                 ),
  //                 const SizedBox(width: 12),
  //                 Expanded(
  //                   child: Text(
  //                     description,
  //                     style: const TextStyle(
  //                       fontSize: 14,
  //                       color: Color(0xFF5A4A3C),
  //                       shadows: [
  //                         Shadow(
  //                           color: Colors.black12,
  //                           offset: Offset(4, 4),
  //                           blurRadius: 2,
  //                         ),
  //                       ],
  //                     ),
  //                     overflow: TextOverflow.ellipsis,
  //                   ),
  //                 ),
  //               ],
  //             ),
  //           ),
  //         ],
  //       ),
  //     ),
  //   );
  // }

}


// class LeftArrowClipper extends CustomClipper<Path> {
//   @override
//   Path getClip(Size size) {
//     final path = Path();
//     path.moveTo(size.width, 0);
//     path.lineTo(size.width * 0.2, 0);
//     path.lineTo(0, size.height / 2);
//     path.lineTo(size.width * 0.2, size.height);
//     path.lineTo(size.width, size.height);
//     path.close();
//     return path;
//   }

//   @override
//   bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
// }

// class _ArrowBorderPainter extends CustomPainter {
//   final Color borderColor;
//   final double borderWidth;
//   final CustomClipper<Path> clipper;

//   _ArrowBorderPainter({
//     required this.borderColor,
//     required this.borderWidth,
//     required this.clipper,
//   });

//   @override
//   void paint(Canvas canvas, Size size) {
//     final path = clipper.getClip(size);
//     final paint = Paint()
//       ..color = borderColor
//       ..style = PaintingStyle.stroke
//       ..strokeWidth = borderWidth;
//     canvas.drawPath(path, paint);
//   }

//   @override
//   bool shouldRepaint(covariant _ArrowBorderPainter oldDelegate) {
//     return borderColor != oldDelegate.borderColor ||
//         borderWidth != oldDelegate.borderWidth ||
//         clipper != oldDelegate.clipper;
//   }
// } 