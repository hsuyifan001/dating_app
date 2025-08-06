import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'home_page.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

class ProfileSetupPage extends StatefulWidget {

  const ProfileSetupPage({super.key});

  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

// class _TagAlignData {
//   final String text;
//   final double dx; // -1 ~ 1
//   final double dy; // -1 ~ 1
//   final Color borderColor;
//   const _TagAlignData(this.text, this.dx, this.dy, this.borderColor);
// }

class CloudPainter extends CustomPainter {
  final Color fillColor;
  final Color borderColor;
  final bool shadow;
  final double borderScale; // 邊框放大比例（通常 1.06）

  CloudPainter({
    required this.fillColor,
    required this.borderColor,
    this.shadow = false,
    this.borderScale = 1.3,
  });

  final List<_Circle> circles = [
    _Circle(0.286, 0.556, 0.107),
    _Circle(0.429, 0.417, 0.125),
    _Circle(0.571, 0.417, 0.107),
    _Circle(0.714, 0.556, 0.107),
    _Circle(0.429, 0.694, 0.107),
    _Circle(0.571, 0.694, 0.125),
  ];

  @override
  void paint(Canvas canvas, Size size) {

    // 下層：深色邊框雲朵（略放大）
    final Paint borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.fill;

    for (final c in circles) {
      final center = Offset(size.width * c.dx, size.height * c.dy);
      final radius = size.width * c.ratio * borderScale;
      canvas.drawCircle(center, radius, borderPaint);
    }

    // 上層：正常填色雲朵
    final Paint fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    for (final c in circles) {
      final center = Offset(size.width * c.dx, size.height * c.dy);
      final radius = size.width * c.ratio;
      canvas.drawCircle(center, radius, fillPaint);
    }

    // （可選）陰影
    if (shadow) {
      final path = Path();
      for (final c in circles) {
        final center = Offset(size.width * c.dx, size.height * c.dy);
        final radius = size.width * c.ratio;
        path.addOval(Rect.fromCircle(center: center, radius: radius));
      }
      canvas.drawShadow(path, Colors.black26, 4.0, true);
    }
  }

  @override
  bool hitTest(Offset position) {
    // 只要點擊位置落在任何一個圓形內，就回傳 true
    for (final c in circles) {
      final center = Offset(160 * c.dx, 90 * c.dy); // 點擊判定，若改圖的大小記得改
      final radius = 160 * c.ratio * borderScale;

      if ((position - center).distance <= radius) {
        return true;
      }
    }
    return false;
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

class _Circle {
  final double dx;
  final double dy;
  final double ratio;

  const _Circle(this.dx, this.dy, this.ratio);
}

class CloudButtonPainted extends StatefulWidget {
  final String text;
  final bool isSelected;
  final VoidCallback onTap;
  final Color borderColor;

  const CloudButtonPainted({
    super.key,
    required this.text,
    required this.onTap,
    required this.isSelected,
    required this.borderColor,
  });

  @override
  State<CloudButtonPainted> createState() => _CloudButtonPaintedState();
}

class _CloudButtonPaintedState extends State<CloudButtonPainted>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller =
        AnimationController(duration: const Duration(milliseconds: 150), vsync: this);
    _scale = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  void _handleTap() {
    _controller.forward().then((_) {
      _controller.reverse();
      widget.onTap();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: ScaleTransition(
        scale: _scale,
        child: CustomPaint(
          painter: CloudPainter(
            fillColor: widget.isSelected ? Colors.orange.shade300 : Colors.white,
            borderColor: widget.borderColor,
            shadow: true,
          ),
          child: Container(
            width: 160,
            height: 90,
            alignment: Alignment.center,
            child: Text(
              widget.text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: widget.isSelected ? Colors.white : Colors.black87,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileSetupPageState extends State<ProfileSetupPage> {
  File? _selectedImage;

  // final List<_TagAlignData> tags = [
  //   _TagAlignData('騎貢丸上學', 0.0, -0.4, Color(0xFF56A3E7)),
  //   _TagAlignData('需要新鮮的肝', -0.9, -0.25, Color(0xFF9BC8F0)),
  //   _TagAlignData('咖啡因成癮', 0.0, -0.1, Color(0xFF5FBCC7)),
  //   _TagAlignData('風好大', 0.9, -0.25, Color(0xFF1B578B)),
  //   _TagAlignData('活動咖', -1.2, 0.0, Color(0xFF5585B0)),
  //   _TagAlignData('美食探險家', 0.05, 0.18, Color(0xFF5E7FC7)),
  //   _TagAlignData('哥布林', 1.1, 0.05, Color(0xFF2449B7)),
  //   _TagAlignData('酒精中毒', -1.0, 0.38, Color(0xFF5D84A6)),
  //   _TagAlignData('愛睡覺', 1.1, 0.35, Color(0xFF4D6FB7)),
  // ];
  final List<String> tags = [
    '美食探險家', '咖啡因成癮', '酒精中毒', '需要\n新鮮的肝',
    '騎貢丸上學', '活動咖', '哥布林', '風好大',
    '愛睡覺', '吃辣王者', '我就爛', '甜食愛好者',
    '運動身體好', '超怕蟲', '貓派', '狗派',
    '拖延症末期', '夜貓子', '笑點低', '愛聽音樂',
    '慢熟', '追劇', '宅宅', '傘被偷',
    '喜歡散步', '教授\n不要當我', '永遠在餓', '忘東忘西',
    '喜歡曬太陽', '文青', '能躺就躺', '鳩咪',
  ];

  final List<String> allTags = [
    '活潑開朗',
    '文靜內向',
    '愛冒險',
    '宅在家',
    '愛運動',
    '喜歡閱讀',
    '動漫迷',
    '電影咖',
    '愛旅行',
    '吃貨',
    '早睡型',
    '夜貓子',
  ];

  final Map<String, String> tagDescriptions = {
    '活潑開朗': '喜歡交朋友，氣氛製造機',
    '文靜內向': '內斂溫柔，慢熱型',
    '愛冒險': '喜歡挑戰新鮮事物',
    '宅在家': '在家也能過得精彩',
    '愛運動': '運動是生活的一部分',
    '喜歡閱讀': '沉浸在書香的世界',
    '動漫迷': '追番是生活日常',
    '電影咖': '熱愛各種電影類型',
    '愛旅行': '探索世界、收集回憶',
    '吃貨': '熱愛美食，總想吃點什麼',
    '早睡型': '生活規律，健康作息',
    '夜貓子': '靈感總在深夜爆發',
  };

  final PageController _pageController = PageController();
  int _currentPage = 0;

  final nameController = TextEditingController();
  final birthdayController = TextEditingController();
  final heightController = TextEditingController();
  String? gender;
  Set<String> matchgender = {};
  String? genderDetail; // 記得刪掉
  String? orientation;
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

  final TextEditingController customSportController = TextEditingController();
  final TextEditingController customPetController = TextEditingController();

  final isInterestsExpanded = {
    '運動': false,
    '寵物': false,
    '電影': false,
  };
  final List<String> mainInterests = [
    '運動', '寵物', '美妝', '動漫', '寫作', '電影', '舞台劇', '逛展覽',
  ];
  final interestsSubtags = {
    '運動': ['排球', '羽球', '桌球', '騎腳踏車', '籃球', '足球', '游泳', '健身', '跑步'],
    '寵物': ['狗派', '貓派'],
    '電影': ['愛情', '科幻', '動作', '喜劇', '恐怖'],
  };
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
  final List<String> educationLevelsList = [
    '大一', '大二', '大三', '大四', '碩士', '博士', '畢業',
  ];
  final List<String> departmentList = [
    '電機系', '資工系', '化工系', '機械系', '生醫系', '材料系',
    '物理系', '化學系', '數學系', '生物系', '心理系', '社會系',
  ];


  void _nextPage() async {    
    // ✅ 延遲一點點再 unfocus，避免鍵盤閃爍
    FocusScope.of(context).unfocus();
    
    if (_currentPage == 0) {
      final name = nameController.text.trim();
      if (name.isEmpty) return;
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('請至少選擇一所學校')),
        );
        return;
      }
    }
    else if (_currentPage == 2) {
      if (selectedTags.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('請至少選擇一個標籤')),
        );
        return;
      }
    }

    if (_currentPage < 3) {
      setState(() => _currentPage++);
      await _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
      FocusScope.of(context).unfocus(); // 換頁的時候關鍵盤(避免更改到前一頁的內容)
    } else {
      _submit();
    }
  }

  void _prevPage() {
    if (_currentPage > 0) {
      setState(() => _currentPage--);
      _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
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
      'height': heightController.text.trim(),
      'educationLevels': selectededucationLevels,
      'department': selectedDepartment,
      'matchSameDepartment': matchSameDepartment,
      'school': school,
      'email': user.email,
      'photoUrl': _photoUrl, // ✅ 加這行
      'createdAt': FieldValue.serverTimestamp(),
    };

    /*if (_selectedImage != null) {
      final ref = FirebaseStorage.instance.ref().child('user_photos').child('${user.uid}.jpg');
      await ref.putFile(_selectedImage!);
      final photoUrl = await ref.getDownloadURL();
      profileData['photoUrl'] = photoUrl;
    }*/
    
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set(profileData);

    if (context.mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage()));
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    nameController.dispose();
    birthdayController.dispose();
    selfIntroController.dispose();
    customSportController.dispose();
    customPetController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 背景圖片對應表
    final backgroundMap = {
      0: 'assets/profile_setup_background.png',
      1: 'assets/school_page_background.png',
      // 2: 'assets/tags_background.png',
    };

    final bg = backgroundMap[_currentPage];

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: BoxDecoration(
          // 根據頁面決定背景顏色或漸層
          color: _currentPage == 2
              ? const Color(0xFFD3F8F3FC)
              : null, // 若是漸層則不能同時設 color
          gradient: _currentPage == 0
              ? const LinearGradient(
                  colors: [
                    Color(0xFF9DD6FF),
                    Color(0xFFFFF3C5),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                )
              : null,
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
                      onTap: () => FocusScope.of(context).unfocus(),
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
                _buildSchoolChoice('國立陽明交通大學', 'nycu'),
                const SizedBox(height: 20),
                _buildSchoolChoice('國立清華大學', 'nthu'),
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
                  backgroundImage: _selectedImage != null ? FileImage(_selectedImage!) : null,
                  child: _selectedImage == null
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
              autofocus: false,
              controller: nameController,
              textAlign: TextAlign.center,
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
                  borderSide: const BorderSide(color: const Color(0xFF1B578B), width: 3),
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
          const SizedBox(height: 24),
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
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.7,
              physics: const NeverScrollableScrollPhysics(), // 禁止滾動，由外部控制
              children: tags.map((tag) {
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
        // Stack(
        //   children: [
        //     // 中央標題
        //     const Positioned(
        //       top: 150,
        //       left: 0,
        //       right: 0,
        //       child: Center(
        //         child: Text(
        //           '選擇個性化標籤',
        //           style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.brown),
        //         ),
        //       ),
        //     ),
        //     // 雲朵按鈕們（以中心為原點相對排列）
        //     ...tags.map((tag) => Align(
        //           alignment: Alignment(tag.dx, tag.dy),
        //           child: CloudButtonPainted(
        //             text: tag.text,
        //             borderColor: tag.borderColor,
        //             isSelected: selectedTags.contains(tag.text),
        //             onTap: () {
        //               setState(() {
        //                 if (selectedTags.contains(tag.text)) {
        //                   selectedTags.remove(tag.text);
        //                 } else {
        //                   selectedTags.add(tag.text);
        //                 }
        //               });
        //             },
        //           ),
        //         )),
        //   ],
        // ),
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
      if (user == null){
        
        return;
      } 

      // debug print
      //print('user.uid: ${user.uid}');
      //print('_selectedImage: ${_selectedImage?.path}');

      final ref = FirebaseStorage.instance
          .ref()
          .child('user_photos')
          .child('${user.uid}.jpg');

      await ref.putFile(_selectedImage!);
      final url = await ref.getDownloadURL();

      setState(() {
        _photoUrl = url;
        _isUploadingPhoto = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('照片上傳成功')),
      );
    } catch (e) {
      setState(() => _isUploadingPhoto = false);
      //print('照片上傳失敗: $e'); // debug print
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('照片上傳失敗：$e')),
      );
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

        const SizedBox(height: 24),
        const Text('身高'),
        const SizedBox(height: 8),
        TextField(
          controller: heightController,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: '請輸入你的身高（公分）',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            filled: true,
            fillColor: Colors.grey[100],
          ),
        ),

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
        Wrap(
          spacing: 8,
          children: departmentList.map((department) => ChoiceChip(
            label: Text(department),
            selected: selectedDepartment == department,
            onSelected: (_) => setState(() => selectedDepartment = department),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          )).toList(),
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