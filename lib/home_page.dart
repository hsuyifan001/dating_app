import 'package:flutter/material.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('LoveMatch')),
      body: const Center(child: Text('歡迎來到交友首頁')),
    );
  }
}
