import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// A full-screen page that collects a school email, sends verification, and waits for the user to confirm.
// Uses an assets background image. Note: repository contains `assets/chat_background.jpg`; using that asset here.

class EmailVerificationPage extends StatefulWidget {
  final User user;
  const EmailVerificationPage({required this.user, super.key});

  @override
  State<EmailVerificationPage> createState() => _EmailVerificationPageState();
}

class _EmailVerificationPageState extends State<EmailVerificationPage> {
  final TextEditingController _emailController = TextEditingController();
  bool _isSending = false;
  bool _sent = false;
  bool _isChecking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailController.text = widget.user.email ?? '';
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  bool _isAllowedSchoolEmail(String email) {
    final e = email.trim();
    return e.endsWith('nycu.edu.tw') || e.endsWith('nthu.edu.tw');
  }

  Future<void> _sendVerification() async {
    final input = _emailController.text.trim();
    if (input.isEmpty) {
      setState(() => _error = '請輸入電子郵件');
      return;
    }
    if (!_isAllowedSchoolEmail(input)) {
      setState(() => _error = '僅允許 nycu.edu.tw 或 nthu.edu.tw 學校信箱');
      return;
    }

    setState(() {
      _isSending = true;
      _error = null;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw FirebaseAuthException(code: 'no-current-user', message: '找不到目前使用者');

      // Update email and send verification
      await currentUser.updateEmail(input);
      await currentUser.sendEmailVerification();

      setState(() {
        _sent = true;
      });
    } on FirebaseAuthException catch (e) {
      // Common case: requires-recent-login
      setState(() {
        _error = '${e.code}: ${e.message ?? e.toString()}';
      });
      if (e.code == 'requires-recent-login') {
        // Show dialog to inform user and then pop(false) so caller can sign out / re-authenticate
        if (mounted) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('需要重新登入'),
              content: const Text('為安全性考量，更新 Email 需要重新登入。請重新登入後再試。'),
              actions: [
                TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('確定')),
              ],
            ),
          );
        }
        // return failure to caller
        if (mounted) Navigator.of(context).pop(false);
      }
    } catch (e) {
      setState(() => _error = '寄送驗證信失敗：$e');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _checkVerifiedAndSave() async {
    setState(() {
      _isChecking = true;
      _error = null;
    });

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('找不到目前使用者');
      await currentUser.reload();
      final refreshed = FirebaseAuth.instance.currentUser;
      final ok = refreshed?.emailVerified ?? false;
      if (!ok) {
        setState(() => _error = '尚未驗證，請先在信箱中點選驗證連結。');
        return;
      }

      final email = _emailController.text.trim();
      String school = '其他';
      if (email.endsWith('nycu.edu.tw')) {
        school = 'NYCU';
      } else if ( email.endsWith('nthu.edu.tw')) {
        school = 'NTHU';
      }

      // write to Firestore
      await FirebaseFirestore.instance.collection('users').doc(currentUser.uid).set({
        'email': email,
        'school': school,
      }, SetOptions(merge: true));

      // success -> return true
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _error = '驗證或儲存失敗：$e');
    } finally {
      if (mounted) setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background image (assume assets/chat_background.jpg exists in project)
          Image.asset(
            'assets/chat_background.jpg',
            fit: BoxFit.cover,
          ),
          Container(color: Colors.black.withOpacity(0.4)),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Card(
                    color: Colors.white.withOpacity(0.95),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('補齊電子郵件以完成帳號設定', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 12),
                          if (!_sent) ...[
                            TextField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              decoration: const InputDecoration(
                                labelText: '學校電子郵件',
                                hintText: 'nycu.edu.tw 或 nthu.edu.tw',
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                TextButton(
                                  onPressed: _isSending ? null : () => Navigator.of(context).pop(false),
                                  child: const Text('取消'),
                                ),
                                ElevatedButton(
                                  onPressed: _isSending ? null : _sendVerification,
                                  child: _isSending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('送出並寄驗證信'),
                                ),
                              ],
                            ),
                          ] else ...[
                            const Text('已寄出驗證信', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 8),
                            const Text('請到你的信箱點選驗證連結，完成後回到此頁按下「我已驗證」。', textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                TextButton(onPressed: _isChecking ? null : () => Navigator.of(context).pop(false), child: const Text('取消')),
                                ElevatedButton(
                                  onPressed: _isChecking ? null : _checkVerifiedAndSave,
                                  child: _isChecking ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('我已驗證'),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
