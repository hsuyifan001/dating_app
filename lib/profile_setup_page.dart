import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'home_page.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

class ProfileSetupPage extends StatefulWidget {
  final String school;

  const ProfileSetupPage({super.key, required this.school});

  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends State<ProfileSetupPage> {
  File? _selectedImage;

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
  String? gender;
  String? genderDetail;
  String? orientation;
  final otherOrientationController = TextEditingController();

  Set<String> selectedTags = {};
  String? selectedMBTI;
  String? selectedZodiac;
  String? _photoUrl;
  bool _isUploadingPhoto = false;

      
  final TextEditingController customSportController = TextEditingController();
  final TextEditingController customPetController = TextEditingController();

  final List<String> sports = ['籃球', '排球', '足球', '桌球', '羽球'];
  final List<String> pets = ['狗', '貓', '小鳥', '爬蟲類', '兔子'];
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

  void _nextPage() async {
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

    if (_currentPage < 6) {
      setState(() => _currentPage++);
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
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

  bool _isLoading = false;

  Future<void> _submit() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    

    final profileData = {
      'name': nameController.text.trim(),
      'birthday': birthdayController.text.trim(),
      'gender': gender,
      'genderDetail': genderDetail,
      'orientation': orientation == '未列出'
          ? otherOrientationController.text.trim()
          : orientation,
      'tags': selectedTags.toList(),
      'mbti': selectedMBTI,
      'zodiac': selectedZodiac,
      'school': widget.school,
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

  Widget _buildProgressBar() => Padding(
        padding: const EdgeInsets.all(12),
        child: LinearProgressIndicator(value: (_currentPage + 1) / 7),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildProgressBar(),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildNamePage(),
                  _buildPhotoUploadPage(),
                  _buildBirthdayPage(),
                  _buildGenderPage(),
                  _buildOrientationPage(),
                  _buildTagPage(),
                  _buildManyTagPage(),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (_currentPage > 0)
                  TextButton(onPressed: _prevPage, child: const Text('上一步')),
                ElevatedButton(
                  onPressed: _nextPage,
                  child: Text(_currentPage == 6 ? '完成' : '下一步'),
                ),
              ],
            ),
          ],
        ),
      ),
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


  Widget _buildPhotoUploadPage() => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      children: [
        const Text('上傳你的照片', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: _pickImage,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircleAvatar(
                radius: 80,
                backgroundImage: _selectedImage != null ? FileImage(_selectedImage!) : null,
                child: _selectedImage == null ? const Icon(Icons.add_a_photo, size: 40) : null,
              ),
              if (_isUploadingPhoto)
                const CircularProgressIndicator(),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          _photoUrl != null ? '已上傳照片 ✅' : '這將成為你的主照片',
          style: TextStyle(color: _photoUrl != null ? Colors.green : Colors.black),
        ),
      ],
    ),
  );

  Widget _buildNamePage() => _buildInputPage(
        title: '姓名',
        controller: nameController,
        hint: '請輸入你的名字',
        subtitle: '此名稱日後便無法更改',
      );

  Widget _buildBirthdayPage() => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('生日', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
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
          ],
        ),
      );

  Widget _buildGenderPage() {
    final isDiverse = gender == '多元性別';
    final diverseOptions = ['性別一', '性別二', '性別三'];

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('性別', style: TextStyle(fontSize: 20)),
          const SizedBox(height: 12),
          for (final g in ['男性', '女性', '多元性別'])
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: OutlinedButton(
                onPressed: () => setState(() {
                  gender = g;
                  genderDetail = null;
                }),
                style: OutlinedButton.styleFrom(
                  backgroundColor: gender == g ? Colors.pink.shade100 : null,
                  minimumSize: const Size(double.infinity, 50),
                ),
                child: Text(g),
              ),
            ),
          if (isDiverse)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Wrap(
                spacing: 8,
                children: diverseOptions.map((opt) => ChoiceChip(
                  label: Text(opt),
                  selected: genderDetail == opt,
                  onSelected: (_) => setState(() => genderDetail = opt),
                )).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOrientationPage() => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('性向', style: TextStyle(fontSize: 20)),
            const SizedBox(height: 12),
            for (final o in ['異性戀', '同性戀', '雙性戀', '無性戀', '摸索中', '未列出'])
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: OutlinedButton(
                  onPressed: () => setState(() => orientation = o),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: orientation == o ? Colors.pink.shade100 : null,
                    minimumSize: const Size(double.infinity, 50),
                  ),
                  child: Text(o),
                ),
              ),
            if (orientation == '未列出')
              TextField(
                controller: otherOrientationController,
                decoration: const InputDecoration(hintText: '請輸入你的性向'),
              ),
          ],
        ),
      );

  Widget _buildTagPage() => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('興趣與標籤', style: TextStyle(fontSize: 20)),
            const SizedBox(height: 12),
            const Text('運動'),
            Wrap(
              spacing: 8,
              children: [
                for (final tag in sports)
                  ChoiceChip(
                    label: Text(tag),
                    selected: selectedTags.contains(tag),
                    onSelected: (selected) {
                      setState(() {
                        selected ? selectedTags.add(tag) : selectedTags.remove(tag);
                      });
                    },
                  ),
              ],
            ),
            TextField(
              controller: customSportController,
              decoration: InputDecoration(
                labelText: '新增其他運動',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    final text = customSportController.text.trim();
                    if (text.isNotEmpty) {
                      setState(() {
                        selectedTags.add(text);
                        customSportController.clear();
                        sports.add(text);
                      });
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('寵物'),
            Wrap(
              spacing: 8,
              children: [
                for (final tag in pets)
                  ChoiceChip(
                    label: Text(tag),
                    selected: selectedTags.contains(tag),
                    onSelected: (selected) {
                      setState(() {
                        selected ? selectedTags.add(tag) : selectedTags.remove(tag);
                      });
                    },
                  ),
              ],
            ),
            TextField(
              controller: customPetController,
              decoration: InputDecoration(
                labelText: '新增其他寵物',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    final text = customPetController.text.trim();
                    if (text.isNotEmpty) {
                      setState(() {
                        selectedTags.add(text);
                        customPetController.clear();
                        pets.add(text);
                      });
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('MBTI'),
            Wrap(
              spacing: 8,
              children: mbtiList.map((type) => ChoiceChip(
                label: Text(type),
                selected: selectedMBTI == type,
                onSelected: (_) => setState(() => selectedMBTI = type),
              )).toList(),
            ),
            const SizedBox(height: 16),
            const Text('星座'),
            Wrap(
              spacing: 8,
              children: zodiacList.map((sign) => ChoiceChip(
                label: Text(sign),
                selected: selectedZodiac == sign,
                onSelected: (_) => setState(() => selectedZodiac = sign),
              )).toList(),
            ),
          ],
        ),
      );

  Widget _buildManyTagPage() => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Stack(
                  children: [
                    Text(
                      '選擇個性化標籤',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        foreground: Paint()
                          ..style = PaintingStyle.stroke
                          ..strokeWidth = 10
                          ..color = Colors.white,
                      ),
                    ),
                    const Text(
                      '選擇個性化標籤',
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
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
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView(
                  children: allTags.map(_buildArrowTag).toList(),
                ),
              ),
            ],
          ),
        ),
      );

  Future<void> _saveProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (selectedTags.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請至少選擇一個標籤')),
      );
      return;
    }

    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'tags': selectedTags.toList(),
      'email': user.email,
      'school': widget.school,
      'createdAt': FieldValue.serverTimestamp(),
    });

    if (context.mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const HomePage()),
      );
    }
  }

  Widget _buildInputPage({
    required String title,
    required TextEditingController controller,
    String? hint,
    String? subtitle,
  }) =>
      Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            TextField(
              controller: controller,
              decoration: InputDecoration(hintText: hint),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ],
        ),
      );
  
  Widget _buildArrowTag(String tag) {
    final isSelected = selectedTags.contains(tag);
    final description = tagDescriptions[tag] ?? '';

    return GestureDetector(
      onTap: () {
        setState(() {
          if (isSelected) {
            selectedTags.remove(tag);
          } else {
            selectedTags.add(tag);
          }
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Add shadow using PhysicalModel for the tag arrow
                  PhysicalModel(
                    color: Colors.transparent,
                    elevation: 6,
                    shadowColor: Colors.black45,
                    borderRadius: BorderRadius.circular(8),
                    child: CustomPaint(
                      painter: _ArrowBorderPainter(
                        borderColor: const Color(0xFF9F806C),
                        borderWidth: 2,
                        clipper: LeftArrowClipper(),
                      ),
                      child: ClipPath(
                        clipper: LeftArrowClipper(),
                        child: Container(
                          width: 82,
                          height: 35,
                          color: isSelected
                              ? Colors.pink.shade300
                              : const Color(0xFFB4F5EE),
                          alignment: Alignment.center,
                          child: Text(
                            tag,
                            style: TextStyle(
                              color: isSelected ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.w600,
                              shadows: [
                                Shadow(
                                  color: Colors.black26,
                                  offset: Offset(1, 2),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      description,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF5A4A3C),
                        shadows: [
                          Shadow(
                            color: Colors.black12,
                            offset: Offset(4, 4),
                            blurRadius: 2,
                          ),
                        ],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

}


class LeftArrowClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.moveTo(size.width, 0);
    path.lineTo(size.width * 0.2, 0);
    path.lineTo(0, size.height / 2);
    path.lineTo(size.width * 0.2, size.height);
    path.lineTo(size.width, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class _ArrowBorderPainter extends CustomPainter {
  final Color borderColor;
  final double borderWidth;
  final CustomClipper<Path> clipper;

  _ArrowBorderPainter({
    required this.borderColor,
    required this.borderWidth,
    required this.clipper,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = clipper.getClip(size);
    final paint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = borderWidth;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ArrowBorderPainter oldDelegate) {
    return borderColor != oldDelegate.borderColor ||
        borderWidth != oldDelegate.borderWidth ||
        clipper != oldDelegate.clipper;
  }
}
