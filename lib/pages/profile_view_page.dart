import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:auto_size_text/auto_size_text.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'story_page.dart';

class ProfileViewPage extends StatefulWidget {
  final String userId;

  const ProfileViewPage({Key? key, required this.userId}) : super(key: key);

  @override
  State<ProfileViewPage> createState() => _ProfileViewPageState();
}

class _ProfileViewPageState extends State<ProfileViewPage> {
  Map<String, dynamic> _data = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final doc = await FirebaseFirestore.instance.collection('users').doc(widget.userId).get();
    if (doc.exists) {
      final raw = doc.data();
      setState(() {
        _data = raw is Map<String, dynamic> ? Map<String, dynamic>.from(raw) : {};
        _loading = false;
      });
    } else {
      setState(() {
        _data = {};
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    double w(double px) => screenWidth * (px / 412);
    double h(double px) => screenHeight * (px / 917);

    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    final name = _data['name'] as String? ?? '使用者';
    final photoUrl = _data['photoUrl'] as String? ?? '';
    final gender = _data['gender'] as String? ?? '';
    final school = _data['school'] as String? ?? '';
    final selfIntro = _data['selfIntro'] as String? ?? '';
    final department = _data['department'] as String? ?? '';
    final educationLevels = _data['educationLevels'] as String? ?? '';
    final tags = List<String>.from(_data['tags'] ?? []);

    // build title block like in AccountPage but with a back arrow
    Widget buildTitleBlock(double screenWidth, double screenHeight) {
      double pxW(double px) => screenWidth * (px / 412);
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // back arrow + paw
          Row(
            children: [
              SizedBox(
                width: pxW(36),
                height: pxW(36),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.arrow_back, color: Colors.black),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: pxW(28),
                child: Image(image: const AssetImage('assets/qing.png')),
              ),
            ],
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 6,
            child: Text(
              '個人資料',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(flex: 1, child: SizedBox()),
        ],
      );
    }

    // profile content (reflowed into a decorated central container)
    final double tagWidth = w(104);
    final double tagSpacing = w(12);
    final double maxWrapWidth = tagWidth * 3 + tagSpacing * 2;
    final AutoSizeGroup myGroup = AutoSizeGroup();

    final profileContent = SingleChildScrollView(
      padding: EdgeInsets.all(w(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: h(10)),

          // 頭像 + 名稱 + icon 疊加（參考 account_page）
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () {
                  showDialog(
                    context: context,
                    builder: (_) => Dialog(
                      backgroundColor: Colors.transparent,
                      insetPadding: const EdgeInsets.all(10),
                      child: Stack(
                        children: [
                          InteractiveViewer(
                            child: Image(
                              image: (photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : const AssetImage('assets/match_default.jpg'),
                              fit: BoxFit.contain,
                            ),
                          ),
                          Positioned(
                            right: 4,
                            top: 4,
                            child: GestureDetector(
                              onTap: () {
                                Navigator.of(context).pop();
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                padding: const EdgeInsets.all(4),
                                child: const Icon(
                                  Icons.close,
                                  size: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
                child: Container(
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
                    backgroundImage: (photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : const AssetImage('assets/match_default.jpg') as ImageProvider,
                    backgroundColor: Colors.transparent,
                  ),
                ),
              ),

              SizedBox(width: w(15)),

              // 姓名區域
              Expanded(
                child: SizedBox(
                  height: w(102),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        name,
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

              // icon
              SizedBox(
                width: w(102),
                height: w(102),
                child: Transform.rotate(
                  angle: 14.53 * 3.1415926535 / 180,
                  child: Image.asset('assets/icon.png', fit: BoxFit.contain),
                ),
              ),
            ],
          ),

          SizedBox(height: h(60)),

          Transform.translate(
            offset: Offset(w(20), 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: h(30),
                  width: w(300),
                  child: AutoSizeText(
                    '學校：${school.isNotEmpty ? school : '尚未填寫'}',
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
                    '學系：${department.isNotEmpty ? department : '尚未填寫'}',
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
                    '在學狀態：${educationLevels!='' ? educationLevels : '尚未填寫'}',
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
                    '性別：${gender.isNotEmpty ? gender : '尚未填寫'}',
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
                    group: myGroup,
                  ),
                ),

                SizedBox(height: h(8)),

                SizedBox(
                  height: h(100),
                  width: w(300),
                  child: SingleChildScrollView(
                    child: AutoSizeText(
                      '${selfIntro.isNotEmpty ? selfIntro : '尚未填寫'}',
                      style: const TextStyle(
                        fontSize: 20,
                        color: Colors.black87,
                        fontWeight: FontWeight.w500,
                      ),
                      minFontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: h(30)),

          // 標籤
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
                            "  ${tags[i]}  ",
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
                    // 使用者的 stories（從 Firestore 抓取），顯示於個人資料與標籤之後
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(widget.userId)
                .collection('stories')
                .orderBy('timestamp', descending: true)
                .snapshots(),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return Padding(
                  padding: EdgeInsets.symmetric(vertical: h(8)),
                  child: const Center(child: Text('目前沒有貼文')),
                );
              }

              // build StoryCard list (reuse main StoryCard for consistent UI)
              final currentUid = FirebaseAuth.instance.currentUser?.uid ?? '';
              final userInfoCache = {widget.userId: {'name': name, 'photoUrl': photoUrl}};

              return Column(
                children: docs.map((d) {
                  final raw = d.data();
                  final data = raw is Map<String, dynamic> ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
                  data['storyId'] = d.id;
                  data['userId'] = widget.userId;
                  data['likes'] = data['likes'] ?? <String>[];

                  return StoryCard(
                    story: data,
                    currentUserId: currentUid,
                    userInfoCache: userInfoCache,
                    onEdit: ({String? storyId, Map<String, dynamic>? existingData}) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('此頁面為檢視模式，無法編輯')));
                    },
                    onDelete: (storyId) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('無刪除權限')));
                    },
                    onToggleLike: (userId, storyId, likes) async {
                      try {
                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(userId)
                            .collection('stories')
                            .doc(storyId)
                            .update({'likes': likes});
                      } catch (e) {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('更新按讚失敗：$e')));
                      }
                    },
                    onShowComments: (userId, storyId) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('請至動態頁面查看留言')));
                    },
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: const Color(0xFCD3F8F3),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(12, 48, 12, 12),
        child: Column(
          children: [
            // top title block
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFFC8CA),
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

            // central decorated container
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
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: profileContent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

}



