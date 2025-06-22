import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'home_page.dart';

class ProfileSetupPage extends StatefulWidget {
  final String school;

  const ProfileSetupPage({super.key, required this.school});

  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends State<ProfileSetupPage> {
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

  final Set<String> selectedTags = {};

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
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
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.pink,
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: const Text('儲存並進入'),
              ),
            ],
          ),
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
