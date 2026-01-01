import 'package:flutter/material.dart';
import 'pages/match_page.dart';
import 'pages/chat_page.dart';
import 'pages/account_page.dart';
import 'pages/activity_page.dart';
import 'pages/story_page.dart';
// import 'package:cloud_firestore/cloud_firestore.dart'; // 新增虛擬使用者用，記得刪
// import 'package:firebase_auth/firebase_auth.dart'; // 新增虛擬使用者用，記得刪

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

  double getBottomNavBarHeight(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    if (screenHeight < 700) {
      return 50; // 小螢幕用小高度
    } else if (screenHeight < 900) {
      return 60; // 中等螢幕
    } else {
      return 70; // 大螢幕
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final navBarHeight = screenHeight / 10;
    return Scaffold(
      //appBar: AppBar(title: const Text('洋青椒')),
      body: _pages[_currentIndex],
      bottomNavigationBar: CustomBottomNavBar(
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        height: navBarHeight,
      ),
    );
  }
}

class CustomBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;
  final double height;

  const CustomBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final itemWidth = screenWidth / 5;

    return Container(
      height: height,
      color: const Color.fromRGBO(255, 200, 202, 1),
      child: Row(
        children: List.generate(5, (index) {
          final isSelected = index == currentIndex;
          return GestureDetector(
            onTap: () => onTap(index),
            child: Container(
              width: itemWidth,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/${_getIconName(index)}.png',
                    width: height * (160 / 264),
                    height: height * (160 / 264),
                  ),
                  Text(
                    _getLabel(index),
                    style: TextStyle(
                      color: isSelected ? const Color.fromARGB(255, 100, 14, 89) : Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  String _getIconName(int index) {
    switch (index) {
      case 0:
        return 'story_icon';
      case 1:
        return 'activity_icon';
      case 2:
        return 'match_icon';
      case 3:
        return 'chat_icon';
      case 4:
        return 'person_profile_icon';
      default:
        return '';
    }
  }

  String _getLabel(int index) {
    switch (index) {
      case 0:
        return '動態';
      case 1:
        return '活動';
      case 2:
        return '配對';
      case 3:
        return '聊天';
      case 4:
        return '個人資料';
      default:
        return '';
    }
  }
}

// 以下是創建虛擬使用者的程式
  /*
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

  @override // 記得刪
  void initState() {
    super.initState();
    _createOrOverwriteFakeUsers();
  }

  Future<void> _createOrOverwriteFakeUsers() async {
    final firestore = FirebaseFirestore.instance;
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;

    final myUid = currentUser.uid;

    WriteBatch batch = firestore.batch();

    for (int i = 1; i <= 15; i++) {
      final fakeUid = 'testUser$i';
      final userDoc = firestore.collection('users').doc(fakeUid);

      List<String> userTags = [tags[(i*17)%32], 
                               tags[(i*19)%32] == tags[(i*17)%32] ? tags[(i*19+1)%32] : tags[(i*19)%32]];
      List<String> userHabits = [mainInterests[(i*3)%8],
                                 mainInterests[(i*5)%8] == mainInterests[(i*3)%8] ? mainInterests[(i*5+1)%8] : mainInterests[(i*5)%8]];
      
      for(int j = 0; j < 2; j++) {
        final tmpHabits = userHabits[j];
        if(interestsSubtags.containsKey(tmpHabits)) {
          final length = interestsSubtags[tmpHabits]?.length;
          userHabits.add(interestsSubtags[tmpHabits]![(i*7)%length!]);
        }
      }

      // set 本身會覆寫（replace）該文件
      batch.set(userDoc, {
        'name': '測試使用者 $i',
        'email': 'test$i@example.com',
        'createdAt': FieldValue.serverTimestamp(),
        'age': 20 + (i % 10),
        'gender': i % 2 == 0 ? '男性' : '女性',
        'tags': userTags,
        'habits': userHabits,

        'matchSchools':  i % 2 == 0 ? 'nycu' : 'nthu',
        'matchGender': ['男性', '女性'].toList(),
        'mbti': mbtiList[i%16],
        'zodiac': zodiacList[i%12],
        'birthday': '${2000 + (i % 10)}/${(i % 12 + 1).toString().padLeft(2, '0')}/${(i % 28 + 1).toString().padLeft(2, '0')}',
        'height': 160 + (i % 20),
        'educationLevels': '大二',
        'department': '電機系',
        'matchSameDepartment': true,
        'school': 'nycu',
        'photoUrl': '',
        'selfIntro': '',
      });

      // 覆寫 likes 文件
      final likeDoc = firestore.collection('likes').doc('${fakeUid}_$myUid');
      batch.set(likeDoc, {
        'timestamp': FieldValue.serverTimestamp(),
        'from': fakeUid,
        'to': myUid,
      });

      if (i % 500 == 0) {
        await batch.commit();
        batch = firestore.batch();
      }
    }

    await batch.commit();

    print('已覆寫15位假使用者及 likes 資料');
  }
  */

// }
