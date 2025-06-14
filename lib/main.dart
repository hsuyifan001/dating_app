import 'package:flutter/material.dart';
import 'register_page.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'profile_setup_page.dart'; // 等下會建立
import 'home_page.dart'; // 你的主交友頁面

void main() async { // 記得awit要配上async
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp()); //MyApp = 你的APP名稱
}


class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '交友軟體',
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
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                '歡迎使用 LoveMatch',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const RegisterPage()),
                  );
                },
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  backgroundColor: Colors.pink,
                ),
                child: const Text('使用學校帳號註冊'),
              ),
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: () async {
                  try {
                    final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
                    if (googleUser == null) return;

                    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

                    final credential = GoogleAuthProvider.credential(
                      accessToken: googleAuth.accessToken,
                      idToken: googleAuth.idToken,
                    );

                    final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
                    final user = userCredential.user;
                    final email = user?.email ?? '';

                    if (!email.endsWith('@nycu.edu.tw') && !email.endsWith('@nthu.edu.tw')) {
                      await FirebaseAuth.instance.signOut();
                      await GoogleSignIn().signOut();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('僅允許 nycu.edu.tw 或 nthu.edu.tw 學校信箱登入')),
                        );
                      }
                      return;
                    }

                    // 檢查是否已經有個人資料
                    final userDoc = await FirebaseFirestore.instance.collection('users').doc(user!.uid).get();

                    if (!userDoc.exists) {
                      // 導向個人資料編輯頁
                      if (context.mounted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const ProfileSetupPage()),
                        );
                      }
                    } else {
                      // 已建立個人資料，進入主畫面
                      if (context.mounted) {
                        Navigator.push(
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
                },
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 50),
                  side: const BorderSide(color: Colors.pink),
                  foregroundColor: Colors.pink,
                ),
                child: const Text('登入'),
              ),

            ],
          ),
        ),
      ),
    );
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

  Future<void> _checkAuth() async {
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

    if (userDoc.exists) {
      // 有個人資料 → 進首頁
      setState(() {
        _startPage = const HomePage();
        _isLoading = false;
      });
    } else {
      // 無個人資料 → 導向編輯頁
      setState(() {
        _startPage = const ProfileSetupPage();
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