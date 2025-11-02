import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'profile_setup_page.dart'; // 等下會建立
import 'home_page.dart';
import 'package:permission_handler/permission_handler.dart'; // ← 新增這行
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/services.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:firebase_app_check/firebase_app_check.dart';

void main() async { // 記得awit要配上async
  WidgetsFlutterBinding.ensureInitialized();
  // 加這一行，鎖定直屏
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await setupFcm();

  await FirebaseAppCheck.instance.activate(
    // For web applications, use reCAPTCHA v3. You'll need to replace 'recaptcha-v3-site-key'
    // with your actual reCAPTCHA v3 site key obtained from the Google reCAPTCHA console.
    webProvider: ReCaptchaV3Provider('recaptcha-v3-site-key'),

    // For Android, Play Integrity Provider is the recommended default.
    // During development, you might use AndroidProvider.debug for easier testing,
    // but remember to switch to Play Integrity for production.
    androidProvider: AndroidProvider.debug,

    // For Apple platforms (iOS/macOS), App Attest is the recommended default for devices.
    // For simulators or specific testing, you might use AppleProvider.debug or Device Check.
    appleProvider: AppleProvider.appAttest, // Or AppleProvider.debug, AppleProvider.deviceCheck
  );
  runApp(const MyApp()); //MyApp = 你的APP名稱
}




Future<void> setupFcm() async {
  try {
    final fcm = FirebaseMessaging.instance;
    await fcm.requestPermission(alert: true, badge: true, sound: true);
    final fcmToken = await fcm.getToken();
    print('FCM 權杖: $fcmToken');
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null && fcmToken != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .set({'fcmToken': fcmToken}, SetOptions(merge: true));
      print('FCM 權杖已儲存至 Firestore: $userId');
    }
    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      if (userId != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .set({'fcmToken': newToken}, SetOptions(merge: true));
        print('FCM 權杖更新: $newToken');
      }
    });
  } catch (e) {
    print('設置 FCM 失敗: $e');
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '洋青椒',
      theme: ThemeData(
        primarySwatch: Colors.pink,
      ),
      home: const AuthGate(), // ← 改這裡
    );
  }
}

class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFE3),
      body: Stack(
        fit: StackFit.expand, // 讓背景圖自動鋪滿
        children: [
          // ✅ 背景圖片
          Image.asset(
            'assets/welcome.png',
            fit: BoxFit.cover,
          ),

          // ✅ 半透明遮罩（可選）
          Container(
            color: const Color.fromARGB(255, 51, 51, 51).withOpacity(0.05), // 淡黑遮罩提升文字對比度
          ),

          // ✅ 前景內容
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Column(
                mainAxisSize: MainAxisSize.min, // 垂直置中
                children: [
                  Image.asset(
                    'assets/icon.png',
                    width: 220,
                  ),
                  Stack(
                    children: [
                      // 外框字（白色描邊）
                      Text(
                        '歡迎使用 洋青椒',
                        style: TextStyle(
                          fontSize: 28,
                          foreground: Paint()
                            ..style = PaintingStyle.stroke
                            ..strokeWidth = 4
                            ..color = Colors.white,
                        ),
                      ),

                      // 內部填色字（黑色 + 陰影）
                      Text(
                        '歡迎使用 洋青椒',
                        style: TextStyle(
                          fontSize: 28,
                          color: Color(0xFF5A4A3C),
                          shadows: [
                            Shadow(
                              offset: Offset(2, 2),
                              blurRadius: 4,
                              color: Colors.black38,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  ElevatedButton.icon(
                    onPressed: () => _signInWithGoogle(context),
                    //icon: const Icon(Icons.login),
                    label: const Text('使用 Google 帳號登入'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Color(0xFFFEECEC),
                      foregroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 50),
                      side: const BorderSide(color: Color(0xFF89C9C2), width: 2),
                    ),
                  ),
                  const SizedBox(height: 200),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

}


Future<void> _signInWithGoogle(BuildContext context) async {
  try {
    final GoogleSignIn googleSignIn = GoogleSignIn();

    // 強制登出，讓使用者每次都能重新選帳號
    await googleSignIn.signOut();

    // 選擇帳號登入
    final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
    if (googleUser == null) return; // 使用者取消登入

    final String email = googleUser.email;
    
    // 登入前先檢查信箱格式
    if (!email.endsWith('@nycu.edu.tw') && !email.endsWith('@nthu.edu.tw') && email != 'qq171846@gmail.com' && email != 'yugapad02@gmail.com') {
      await googleSignIn.signOut();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('僅允許 nycu.edu.tw 或 nthu.edu.tw 學校信箱登入')),
        );
      }
      return;
    }
    
    // 通過信箱驗證後繼續取得 token 並登入 Firebase
    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
    final user = userCredential.user;

    if (user == null) {
      throw Exception('Firebase 使用者為空');
    }

    // 檢查是否已有個人資料
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();

    if (context.mounted) {
      if (!userDoc.exists || !(userDoc.data() as Map<String, dynamic>).containsKey('name')) {
        // 第一次登入 → 導向學校選擇頁面
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const ProfileSetupPage()),
        );
      }
      else {
        // 已建立個人資料，進入主頁
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const HomePage()),
        );
      }
    }

  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('登入失敗：$e')),
      );
    }
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _isLoading = true;
  Widget? _startPage;

  @override
  void initState() {
    super.initState();
    _checkAuth();
  }

Future<void> _requestPermissions() async {
  final statuses = await [
    Permission.photos,
    Permission.storage,
  ].request();

  if (statuses[Permission.photos] != PermissionStatus.granted &&
      statuses[Permission.storage] != PermissionStatus.granted) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('請允許權限以使用照片與檔案功能')),
      );
    }
  }
}


  Future<void> _checkAuth() async {
    await _requestPermissions();
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      // 未登入 → 歡迎頁面
      setState(() {
        _startPage = const WelcomePage();
        _isLoading = false;
      });
      return;
    }

    // 檢查 Firestore 裡是否已有該使用者的個人資料
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

    if ((!userDoc.exists || !(userDoc.data() as Map<String, dynamic>).containsKey('name'))) {
      // 有個人資料 → 進首頁
      setState(() {
        _startPage = const HomePage();
        _isLoading = false;
      });
    } else {
      // 無個人資料 → 導向編輯頁
      setState(() {
        _startPage = const WelcomePage();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    return _startPage!;
  }
}