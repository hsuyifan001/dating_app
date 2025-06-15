import 'package:flutter/material.dart';
import 'pages/match_page.dart';
import 'pages/chat_page.dart';
import 'pages/account_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const MatchPage(),
    const ChatPage(),
    const AccountPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('洋青椒')),
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: Colors.pink,
        unselectedItemColor: Colors.grey,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.favorite), label: '配對'),
          BottomNavigationBarItem(icon: Icon(Icons.chat), label: '聊天'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: '帳號'),
        ],
      ),
    );
  }
}
