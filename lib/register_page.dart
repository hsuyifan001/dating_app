import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'main.dart'; // 導回 WelcomePage 的入口

class RegisterPage extends StatelessWidget {
  const RegisterPage({super.key});

  Future<void> _signInWithGoogle(BuildContext context) async {
    try {
      final GoogleSignIn googleSignIn = GoogleSignIn();

      // 強制登出，讓每次都重新選帳號
      await googleSignIn.signOut();

      // 使用 Google Sign-In 選帳號
      final GoogleSignInAccount? googleUser = await googleSignIn.signIn();
      if (googleUser == null) return; // 使用者取消登入

      final String email = googleUser.email;

      // 先檢查 email 網域
      if (!email.endsWith('@nycu.edu.tw') && !email.endsWith('@nthu.edu.tw')) {
        await googleSignIn.signOut();

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('只允許使用 nycu.edu.tw 或 nthu.edu.tw 學校信箱註冊')),
          );
        }
        return;
      }

      // 通過驗證才繼續取得 token 並登入 Firebase
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await FirebaseAuth.instance.signInWithCredential(credential);

      // 登入成功後導回主頁
      if (context.mounted) {
        Navigator.popUntil(context, (route) => route.isFirst);
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
