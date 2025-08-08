import 'package:flutter/material.dart';
import 'pages/match_page.dart';
import 'pages/chat_page.dart';
import 'pages/account_page.dart';
import 'pages/activity_page.dart';
import 'pages/story_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const StoryPage(),
    const ActivityPage(),
    const MatchPage(),
    const ChatPage(),
    const AccountPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      //appBar: AppBar(title: const Text('洋青椒')),
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: Color.fromARGB(255, 100, 14, 89),
        unselectedItemColor: Colors.grey,
        backgroundColor: const Color.fromRGBO(255, 200, 202, 1), // ✅ 設定背景色
        type: BottomNavigationBarType.fixed, // ✅ 加上這行才能套用背景色
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: [
          BottomNavigationBarItem(icon: Image.asset('assets/match_icon.png', width: 79, height: 79), label: '動態'),
          BottomNavigationBarItem(icon: Image.asset('assets/match_icon.png', width: 79, height: 79), label: '活動'),
          BottomNavigationBarItem(icon: Image.asset('assets/match_icon.png', width: 79, height: 79), label: '配對'),
          BottomNavigationBarItem(icon: Image.asset('assets/chat_icon.png',  width: 79, height: 79), label: '聊天'),
          BottomNavigationBarItem(icon: Image.asset('assets/person_profile_icon.png', width: 79, height: 79), label: '個人資料'),
        ],
      ),
    );
  }
}
