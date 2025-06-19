import 'package:flutter/material.dart';
import 'profile_setup_page.dart';

class SchoolSelectPage extends StatelessWidget {
  const SchoolSelectPage({super.key});

  void _selectSchool(BuildContext context, String schoolCode) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ProfileSetupPage(school: schoolCode),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ✅ 背景圖片
          Image.asset(
            'assets/school_page_background.png',
            fit: BoxFit.cover,
          ),

          // ✅ 遮罩
          Container(
            color: Colors.black.withOpacity(0.05),
          ),

          // ✅ 內容
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    children: [
                      Text(
                        '選擇學校',
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
                        '選擇學校',
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
                              color: Color(0x80000000), // 半透明黑
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 48),
                  ElevatedButton(
                    onPressed: () => _selectSchool(context, 'nycu'),
                    style: ElevatedButton.styleFrom(
                      side: const BorderSide(
                        color: Color(0xFF89C9C2),
                        width: 3,
                      ),
                      backgroundColor: Color(0xFFFEECEC),
                      foregroundColor: Color(0xFF5A4A3C),
                      minimumSize: const Size(double.infinity, 60),
                    ),
<<<<<<< HEAD
                    child: const Text('國立陽明交通大學',
                      style: TextStyle(
                            fontFamily: 'Kiwi Maru',
                            fontWeight: FontWeight.w400,
                            fontSize: 18,
                            height: 1.0,
                            letterSpacing: 0.0,
                            color: Color(0xFF5A4A3C),
                            
                          ),
                      ),
=======
                    child: const Text('國立陽明交通大學', style: TextStyle(fontSize: 18)),
>>>>>>> 912882a30361e98a077aa89ca8623afee5e123fd
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () => _selectSchool(context, 'nthu'),
                    style: ElevatedButton.styleFrom(
                      side: const BorderSide(
                        color: Color(0xFF89C9C2),
                        width: 3,
                      ),
                      backgroundColor: Color(0xFFFEECEC),
                      foregroundColor: Color(0xFF5A4A3C),
                      minimumSize: const Size(double.infinity, 60),
                    ),
<<<<<<< HEAD
                    child: const Text('國立清華大學',
                      style: TextStyle(
                            fontFamily: 'Kiwi Maru',
                            fontWeight: FontWeight.w400,
                            fontSize: 18,
                            height: 1.0,
                            letterSpacing: 0.0,
                            color: Color(0xFF5A4A3C),
                            
                          ),
                      ),
=======
                    child: const Text('國立清華大學', style: TextStyle(fontSize: 18)),
>>>>>>> 912882a30361e98a077aa89ca8623afee5e123fd
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
