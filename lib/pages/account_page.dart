import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../main.dart'; // 或調整為你 WelcomePage 的正確路徑

class AccountPage extends StatefulWidget {
  const AccountPage({super.key});

  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  final nameController = TextEditingController();
  final bioController = TextEditingController();
  bool isLoading = true;
  bool isEditing = false;
  String email = '';
  String? photoURL;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();

    if (doc.exists) {
      final data = doc.data()!;
      nameController.text = data['name'] ?? '';
      bioController.text = data['bio'] ?? '';
      email = data['email'] ?? user.email ?? '';
      photoURL = user.photoURL;
    }

    setState(() {
      isLoading = false;
    });
  }

  Future<void> _saveProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final name = nameController.text.trim();
    final bio = bioController.text.trim();

    await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
      'name': name,
      'bio': bio,
    });

    setState(() {
      isEditing = false;
    });

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('個人資料已更新')),
      );
    }
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    await GoogleSignIn().signOut();
    if (context.mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const WelcomePage()),
        (route) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundImage: photoURL != null ? NetworkImage(photoURL!) : null,
            child: photoURL == null ? const Icon(Icons.person, size: 40) : null,
          ),
          const SizedBox(height: 16),
          Text(email),
          const SizedBox(height: 24),
          TextField(
            controller: nameController,
            readOnly: !isEditing,
            decoration: const InputDecoration(labelText: '名稱'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: bioController,
            readOnly: !isEditing,
            decoration: const InputDecoration(labelText: '簡介'),
            maxLines: 3,
          ),
          const SizedBox(height: 24),

          if (isEditing)
            ElevatedButton.icon(
              onPressed: _saveProfile,
              icon: const Icon(Icons.save),
              label: const Text('儲存變更'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.pink,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  isEditing = true;
                });
              },
              icon: const Icon(Icons.edit),
              label: const Text('編輯個人資料'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.pink,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 50),
              ),
            ),

          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout),
            label: const Text('登出'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
              side: const BorderSide(color: Colors.pink),
              foregroundColor: Colors.pink,
            ),
          ),
        ],
      ),
    );
  }
}
