import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'main.dart'; // 導回 WelcomePage 的入口

class RegisterPage extends StatelessWidget {
  const RegisterPage({super.key});

  Future<void> _signInWithGoogle(BuildContext context) async {
  try {
    final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) return;

    final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    // 使用 Firebase 認證登入
    final userCredential = await FirebaseAuth.instance.signInWithCredential(credential);
    final email = userCredential.user?.email ?? '';

    // 驗證 email 網域
    if (email.endsWith('@nycu.edu.tw') || email.endsWith('@nthu.edu.tw')) {
      if (context.mounted) {
        Navigator.popUntil(context, (route) => route.isFirst);
      }
    } else {
      // 如果不是學校信箱，登出並顯示錯誤
      await FirebaseAuth.instance.signOut();
      await GoogleSignIn().signOut();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('只允許使用 nycu.edu.tw 或 nthu.edu.tw 學校信箱註冊')),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('註冊')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: ElevatedButton.icon(
            onPressed: () => _signInWithGoogle(context),
            icon: const Icon(Icons.login),
            label: const Text('使用 Google 帳號註冊'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 50),
              side: const BorderSide(color: Colors.black12),
            ),
          ),
        ),
      ),
    );
  }
}
