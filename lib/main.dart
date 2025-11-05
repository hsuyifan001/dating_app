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
import 'services/fcm_service.dart';
import 'package:flutter/services.dart';
// 'timeago' 未使用，保留註解以便將來需要時再啟用
// import 'package:timeago/timeago.dart' as timeago;
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';

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
    print('FCM 權杖(暫存): $fcmToken');

    // 暫存 token，不立即建立 users doc
    FcmService.setPendingToken(fcmToken);

    // 若已登入且 user doc 已存在，嘗試寫入
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId != null) {
      await FcmService.saveTokenIfUserProfileExists(userId);
    }

    FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
      print('FCM 權杖 refresh(暫存): $newToken');
      FcmService.setPendingToken(newToken);
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FcmService.saveTokenIfUserProfileExists(uid);
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

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  bool _showDemoLogin = false;
  bool _loadingConfig = true;

  @override
  void initState() {
    super.initState();
    _loadRemoteConfig();
  }

  Future<void> _loadRemoteConfig() async {
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;
      await remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: const Duration(seconds: 0),
      ));
      await remoteConfig.fetchAndActivate();
      final show = remoteConfig.getBool('showDemoLogin');
      setState(() {
        _showDemoLogin = show;
        _loadingConfig = false;
      });
    } catch (e) {
      // 若失敗則預設不顯示按鈕，並紀錄錯誤
      print('RemoteConfig 讀取失敗: $e');
      setState(() {
        _loadingConfig = false;
        _showDemoLogin = false;
      });
    }
  }

  Future<void> _showEmailPasswordDialog() async {
    final formKey = GlobalKey<FormState>();
    String email = '';
    String password = '';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Email / 密碼 登入'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  decoration: const InputDecoration(labelText: '電子郵件'),
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) => (v == null || v.isEmpty) ? '請輸入電子郵件' : null,
                  onSaved: (v) => email = v!.trim(),
                ),
                TextFormField(
                  decoration: const InputDecoration(labelText: '密碼'),
                  obscureText: true,
                  validator: (v) => (v == null || v.isEmpty) ? '請輸入密碼' : null,
                  onSaved: (v) => password = v!.trim(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (!formKey.currentState!.validate()) return;
                formKey.currentState!.save();
                try {
                  final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
                    email: email,
                    password: password,
                  );
                  final user = cred.user;
                  Navigator.of(dialogContext).pop();
                  if (user != null) {
                    await _postSignInNavigation(context, user);
                  }
                } catch (e) {
                  // 顯示錯誤訊息
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(dialogContext).showSnackBar(
                      SnackBar(content: Text('登入失敗：$e')),
                    );
                  }
                }
              },
              child: const Text('登入'),
            ),
          ],
        );
      },
    );
  }

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

                  if (_loadingConfig) const SizedBox(height: 12),

                  if (!_loadingConfig && _showDemoLogin) ...[
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: () => _showEmailPasswordDialog(),
                      label: const Text('使用 Email/密碼登入 (Demo)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black,
                        minimumSize: const Size(double.infinity, 50),
                        side: const BorderSide(color: Color(0xFF89C9C2), width: 2),
                      ),
                    ),
                  ],

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

    // 先嘗試靜默登入（若使用者先前已授權）
    GoogleSignInAccount? googleUser = await googleSignIn.signInSilently();
    if (googleUser == null) {
      // 若靜默登入失敗，才開啟帳號選擇流程
      googleUser = await googleSignIn.signIn();
    }
    if (googleUser == null) return; // 使用者取消登入

    final String email = googleUser.email;
    
    // 登入前先檢查信箱格式
    if (!email.endsWith('@nycu.edu.tw') && !email.endsWith('@nthu.edu.tw') && email != 'qq171846@gmail.com') {
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

    await _postSignInNavigation(context, user);

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
  bool _permissionsChecked = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _requestPermissions();
    if (mounted) {
      setState(() {
        _permissionsChecked = true;
      });
    }
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

  @override
  Widget build(BuildContext context) {
    if (!_permissionsChecked) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        final user = authSnap.data;
        if (user == null) {
          // 未登入 → 顯示歡迎 / 登入頁
          return const WelcomePage();
        }

        // 已登入 → 檢查 Firestore 是否有個人資料
        return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
          builder: (context, userDocSnap) {
            if (userDocSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            if (userDocSnap.hasError) {
              return const Scaffold(body: Center(child: Text('讀取使用者資料失敗')));
            }

            final doc = userDocSnap.data;
            final hasProfile = doc != null && (doc.data()?['name'] != null);

            if (hasProfile) {
              return const HomePage();
            } else {
              return const ProfileSetupPage();
            }
          },
        );
      },
    );
  }
}

Future<void> _postSignInNavigation(BuildContext context, User user) async {
  try {
    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

    if (context.mounted) {
      if (!userDoc.exists || !(userDoc.data() as Map<String, dynamic>).containsKey('name')) {
        // 第一次登入 → 導向學校選擇頁面
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const ProfileSetupPage()),
        );
      } else {
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
        SnackBar(content: Text('登入後導向失敗：$e')),
      );
    }
  }
}