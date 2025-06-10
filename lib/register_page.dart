import 'package:flutter/material.dart';

class RegisterPage extends StatelessWidget {
  const RegisterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('註冊')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: ElevatedButton.icon(
            onPressed: () {
              // TODO: 實作 Google 登入
            },
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
