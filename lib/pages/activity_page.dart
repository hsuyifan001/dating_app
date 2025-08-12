import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as parser;
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'dart:typed_data';

class Activity {
  final String title;
  final String url;
  final String source;

  Activity(this.title, this.url, this.source);

  String get id => md5.convert(utf8.encode(url)).toString();

  Map<String, dynamic> toJson({String? description}) {
    return {
      'title': title,
      'url': url,
      'source': source,
      'description': description ?? '',
      'createdAt': FieldValue.serverTimestamp(),
      'likedBy': [],
      'groupId': null,
      'groupLimit': 5,
      'date': null,
    };
  }
}

class ActivityPage extends StatefulWidget {
  const ActivityPage({super.key});

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();
  String? currentUserId;

  File? selectedImage;
  String? locationText;

  @override
  void initState() {
    super.initState();
    final user = _auth.currentUser;
    if (user != null) {
      currentUserId = user.uid;
    }
    _fetchAndSaveActivities();
    fetchAndSaveNTHUActivities();
    fetchAndSaveHSINActivities();
  }

  Future<bool> canCreateActivity(String userId) async {
    final today = DateFormat('yyyyMMdd').format(DateTime.now());
    final docRef = _firestore.collection('users').doc(userId).collection('activityCreate').doc(today);
    final doc = await docRef.get();

    if (doc.exists) {
      final data = doc.data()!;
      final list = List.from(data['activityCreate'] ?? []);
      return list.length < 3;
    } else {
      return true;
    }
  }

  Future<void> updateCreateCount(String userId, String activityId) async {
    final today = DateFormat('yyyyMMdd').format(DateTime.now());
    final docRef = _firestore.collection('users').doc(userId).collection('activityCreate').doc(today);

    await _firestore.runTransaction((txn) async {
      final snapshot = await txn.get(docRef);
      List activityList = [];

      if (snapshot.exists) {
        activityList = List.from(snapshot['activityCreate'] ?? []);
      }

      activityList.add(activityId);
      final reachLimit = activityList.length >= 3;

      txn.set(docRef, {
        'activityCreate': activityList,
        'reachLimit': reachLimit,
      });
    });
  }

  Future<String> uploadImage(File file) async {
    final Uint8List? compressedImage = await FlutterImageCompress.compressWithFile(
      file.path,
      minWidth: 800,  // 降低解析度
      minHeight: 800,
      quality: 70,    // 壓縮品質
      format: CompressFormat.jpeg,
    );

    if (compressedImage == null) {
      throw Exception('壓縮圖片失敗');
    }

    // 2️⃣ 上傳壓縮後的檔案
    final ref = _storage.ref().child(
      'activity_images/${DateTime.now().millisecondsSinceEpoch}.jpg',
    );

    await ref.putData(
      compressedImage,
      SettableMetadata(contentType: 'image/jpeg'),
    );

    // 3️⃣ 回傳下載 URL
    return await ref.getDownloadURL();
  }


  //URL parser
  Future<String> fetchDetailDescriptionIfValid(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return '';

      final document = parser.parse(response.body);

      final mainDiv = document.querySelector('div.main');
      final containerDiv = document.querySelector('#fs.container');
      final detailDiv = document.querySelector('div.ap > div.detail');

      if (mainDiv == null || containerDiv == null || detailDiv == null) {
        return '';
      }

      final editorDiv = detailDiv.querySelector('.editor');
      if (editorDiv == null) return '';

      return editorDiv.text.trim();
    } catch (e) {
      print('抓取活動詳細頁失敗: $e');
      return '';
    }
  }

  Future<void> _fetchAndSaveActivities() async {
    final url = 'https://osa.nycu.edu.tw/osa/ch/app/data/list?module=nycu0085&id=3494';
    final response = await http.get(Uri.parse(url));

    if (response.statusCode != 200) {
      throw Exception('網站請求失敗');
    }

    final document = parser.parse(response.body);
    final items = document.querySelectorAll('div.newslist > ul > li');
    

    for (var item in items) {
      final aTag = item.querySelector('a');
      if (aTag != null) {
        final infoDiv = aTag.querySelector('div.info');
        String category = '';
        if (infoDiv != null) {
          final pTags = infoDiv.querySelectorAll('p');
          for (var p in pTags) {
            final text = p.text.trim();
            if (text.startsWith('分類：')) {
              category = text.replaceFirst('分類：', '').trim();
              break;
            }
          }
        }

        if (category != '校外訊息' && category != '校內活動') continue;

        final title = aTag.attributes['title'] ?? '';
        final href = aTag.attributes['href'] ?? '';
        final fullUrl = 'https://osa.nycu.edu.tw$href';

        final activity = Activity(title, fullUrl, 'nycu');
        final description = await fetchDetailDescriptionIfValid(fullUrl);
        final docRef = _firestore.collection('activities').doc(activity.id);
        final doc = await docRef.get();

        if (!doc.exists) {
          await docRef.set(activity.toJson(description: description));
        }

        
      }
    }

  }

  Future<void> fetchAndSaveHSINActivities() async {
    final url = 'https://tjm.tainanoutlook.com/hsinchu';
    final firestore = FirebaseFirestore.instance;
    final response = await http.get(Uri.parse(url), headers: {
      'User-Agent': 'Mozilla/5.0',
    });

    if (response.statusCode != 200) {
      print('Error fetching $url - Status: ${response.statusCode}');
      return;
    }

    final document = parser.parse(response.body);

    final imgElements =document.querySelectorAll('#blazy-3d03bf26a8e-1 > li > div > div > span > div > a > img');
    // 取得對應的 <a> 標籤
    final aElements =  document.querySelectorAll('#blazy-3d03bf26a8e-1 > li > div > div > span > div > a');


    for (int i = 0; i < imgElements.length && i < aElements.length; i++) {
      final href = aElements[i].attributes['href'];
      final title =
          imgElements[i].attributes['title'] ?? aElements[i].text.trim() ?? "無標題";

      if (href == null || href.isEmpty) {
        continue;
      }

      final activity = Activity(title, href, 'hsinchu');

      final docRef = firestore.collection('activities').doc(activity.id);
      final doc = await docRef.get();

      if (!doc.exists) {
        await docRef.set(activity.toJson());
        print('Saved: $title');
      } else {
        print('Already exists: $title');
      }
  }
    
  }

  Future<void> fetchAndSaveNTHUActivities() async {
    final firestore = FirebaseFirestore.instance;
    final ajaxUrls = [
      'https://bulletin.site.nthu.edu.tw/app/index.php?Action=mobileloadmod&Type=mobile_rcg_mstr&Nbr=5083',
      'https://bulletin.site.nthu.edu.tw/app/index.php?Action=mobileloadmod&Type=mobile_rcg_mstr&Nbr=5085',
    ];

    for (final url in ajaxUrls) {
      final response = await http.get(Uri.parse(url), headers: {
        'User-Agent': 'Mozilla/5.0',
      });

      if (response.statusCode != 200) {
        print('Error fetching $url - Status: ${response.statusCode}');
        continue;
      }

      final document = parser.parse(response.body);

      final aTags = document.querySelectorAll('a');

      for (var a in aTags) {
        final href = a.attributes['href'];
        var title = a.attributes['title'] ?? a.text.trim();

        if (title == "更多..." || href == null || href.isEmpty) {
          continue;
        }

        final activity = Activity(title, href, 'nthu');

        final docRef = firestore.collection('activities').doc(activity.id);
        final doc = await docRef.get();

        if (!doc.exists) {
          await docRef.set(activity.toJson());
          print('Saved: $title');
        } else {
          print('Already exists: $title');
        }
      }
    }
  }

  //URL parser end

  void _showCreateActivityDialog() {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    final groupLimitController = TextEditingController(text: '5');
    final locationController = TextEditingController();
    DateTime? selectedDateTime;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('建立新活動'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(controller: titleController, decoration: const InputDecoration(labelText: '活動名稱')),
              TextField(controller: descriptionController, decoration: const InputDecoration(labelText: '活動說明')),
              TextField(controller: locationController, decoration: const InputDecoration(labelText: '地點')),
              TextButton(
                onPressed: () async {
                  final date = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime(2100));
                  if (date == null) return;
                  final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
                  if (time == null) return;
                  setState(() {
                    selectedDateTime = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                  });
                },
                child: const Text('選擇時間')
              ),
              TextField(controller: groupLimitController, decoration: const InputDecoration(labelText: '人數上限'), keyboardType: TextInputType.number),
              ElevatedButton(
                onPressed: () async {
                  final picked = await _picker.pickImage(source: ImageSource.gallery);
                  if (picked != null) {
                    setState(() => selectedImage = File(picked.path));
                  }
                },
                child: const Text('上傳圖片'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
          ElevatedButton(
            onPressed: () async {
              if (!await canCreateActivity(currentUserId!)) return;

              final title = titleController.text.trim();
              final desc = descriptionController.text.trim();
              final location = locationController.text.trim();
              final limit = int.tryParse(groupLimitController.text.trim()) ?? 5;

              if (title.isEmpty || selectedDateTime == null) return;

              String? imageUrl;
              if (selectedImage != null) {
                imageUrl = await uploadImage(selectedImage!);
              }

              final newActivity = {
                'title': title,
                'description': desc,
                'location': location,
                'imageUrl': imageUrl,
                'date': Timestamp.fromDate(selectedDateTime!),
                'url': '',
                'source': 'user',
                'createdAt': FieldValue.serverTimestamp(),
                'likedBy': [currentUserId],
                'groupId': null,
                'groupLimit': limit,
                'creatorId': currentUserId,
              };

              final docRef = await _firestore.collection('activities').add(newActivity);
              await updateCreateCount(currentUserId!, docRef.id);

              Navigator.pop(context);
              setState(() {});
            },
            child: const Text('建立'),
          )
        ],
      ),
    );
  }

  void _confirmDeleteActivity(DocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    if (data['creatorId'] != currentUserId) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('確認刪除'),
        content: const Text('確定要刪除這個活動嗎？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('刪除')),
        ],
      ),
    );

    if (confirmed == true) {
      await doc.reference.delete();
      setState(() {});
    }
  }

  void _openMyActivitiesPage() async {
    if (currentUserId == null) return;

    final snapshot = await _firestore
        .collection("users")
        .doc(currentUserId)
        .collection("activityCreate")
        .get();

    List<Map<String, dynamic>> createdActivities = [];

    for (var doc in snapshot.docs) {
      final List<dynamic> list = doc.data()['activityCreate'] ?? [];
      for (var item in list) {
        final actDoc = await _firestore.collection("activities").doc(item).get();
        if (actDoc.exists) {
          createdActivities.add({...?actDoc.data(), 'docId': actDoc.id});
        }
      }
    }

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text("我創建的活動")),
          body: ListView.builder(
            itemCount: createdActivities.length,
            itemBuilder: (context, index) {
              final data = createdActivities[index];
              return Card(
                margin: const EdgeInsets.all(12),
                child: ListTile(
                  leading: data['imageUrl'] != null
                      ? Image.network(data['imageUrl'], width: 50, height: 50, fit: BoxFit.cover)
                      : const Icon(Icons.event),
                  title: Text(data['title'] ?? ''),
                  subtitle: Text(data['location'] ?? ''),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () async {
                      final docId = data['docId'];
                      await _firestore.collection('activities').doc(docId).delete();
                      setState(() {});
                      Navigator.pop(context);
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (currentUserId == null) {
      return const Scaffold(
        body: Center(child: Text('尚未登入，請先登入帳號')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('活動推播'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _showCreateActivityDialog,
          ),
          IconButton(
            icon: const Icon(Icons.list_alt_outlined),
            onPressed: _openMyActivitiesPage,
          ),
        ],
      ),
      body: FutureBuilder<QuerySnapshot>(
        future: _firestore.collection('activities').orderBy('createdAt', descending: true).get(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(child: Text('目前沒有活動'));
          }

          final docs = snapshot.data!.docs.where((doc) {
            final likedBy = List<String>.from(doc['likedBy'] ?? []);
            return !likedBy.contains(currentUserId);
          }).toList();

          if (docs.isEmpty) {
            return const Center(child: Text('你已看完所有活動了！'));
          }

          final currentDoc = docs.first;
          final data = currentDoc.data() as Map<String, dynamic>;

          return Column(
            children: [
              Expanded(
                child: Card(
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (data['imageUrl'] != null)
                          Center(
                            child: Image.network(data['imageUrl'], height: 150),
                          ),
                        Text(data['title'] ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        if (data['location'] != null)
                          Text('地點：${data['location']}', style: const TextStyle(color: Colors.black87)),
                        if (data['date'] != null)
                          Text('時間：${DateFormat('yyyy-MM-dd HH:mm').format((data['date'] as Timestamp).toDate())}'),
                        const SizedBox(height: 8),
                        Text(data['description'] ?? '', maxLines: 5, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 8),
                        if (data['url'] != null && data['url'] != '')
                          Text(data['url'], style: const TextStyle(color: Colors.blue)),
                        const SizedBox(height: 12),
                        if (data['creatorId'] == currentUserId)
                          Align(
                            alignment: Alignment.centerRight,
                            child: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _confirmDeleteActivity(currentDoc),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red, size: 40),
                    onPressed: () {
                      setState(() {});
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.favorite, color: Colors.green, size: 40),
                    onPressed: () async {
                      final likedBy = List<String>.from(data['likedBy'] ?? []);
                      final groupLimit = data['groupLimit'] ?? 5;
                      final groupId = data['groupId'];

                      await currentDoc.reference.update({
                        'likedBy': FieldValue.arrayUnion([currentUserId])
                      });

                      if (groupId == null && likedBy.length + 1 >= groupLimit) {
                        final newGroup = await _firestore.collection('groupChats').add({
                          'activityId': currentDoc.id,
                          'members': [...likedBy, currentUserId],
                          'createdAt': FieldValue.serverTimestamp(),
                        });

                        await currentDoc.reference.update({
                          'groupId': newGroup.id
                        });
                      }

                      setState(() {});
                    },
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          );
        },
      ),
    );
  }
}
  
