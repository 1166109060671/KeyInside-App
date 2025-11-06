import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../app/app_routes.dart';

/// ใช้ครอบหน้าใด ๆ ที่ต้องการบังคับให้ Login/Verified/Admin ก่อนเข้า
class AuthGuardPage extends StatefulWidget {
  const AuthGuardPage({
    super.key,
    required this.child,
    this.requireVerified = false,
    this.requireAdmin = false,
  });

  final Widget child;
  final bool requireVerified;
  final bool requireAdmin;

  @override
  State<AuthGuardPage> createState() => _AuthGuardPageState();
}

class _AuthGuardPageState extends State<AuthGuardPage> {
  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final routeName = ModalRoute.of(context)?.settings.name ?? AppRoutes.catalogList;

    // 1) ยังไม่ล็อกอิน → ส่งไปหน้า Login
    if (user == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (ModalRoute.of(context)?.isCurrent != true) return;
        Navigator.pushReplacementNamed(
          context,
          AppRoutes.login,
          arguments: {
            'redirectTo': routeName,
            'arguments': ModalRoute.of(context)?.settings.arguments,
          },
        );
      });
      return const SizedBox.shrink();
    }

    // 2) ต้อง verify email ก่อน?
    if (widget.requireVerified && !(user.emailVerified)) {
      return _RequireVerifyPanel(
        onRefresh: _refresh,
        onSendVerify: _sendVerify,
      );
    }

    // 3) ต้องเป็น admin?
    if (widget.requireAdmin) {
      return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        future: FirebaseFirestore.instance.collection('users').doc(user.uid).get(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }

          final data = snap.data?.data() ?? {};
          final role = (data['role'] ?? '').toString().toLowerCase();

          if (role != 'admin') {
            return const _ForbiddenPage();
          }
          return widget.child; // ผ่าน
        },
      );
    }

    // ผ่านทุกเงื่อนไข
    return widget.child;
  }

  Future<void> _refresh() async {
    try {
      await FirebaseAuth.instance.currentUser?.reload();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  Future<void> _sendVerify() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await user.sendEmailVerification();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ส่งอีเมลยืนยันแล้ว โปรดตรวจกล่องจดหมาย/สแปม')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ส่งอีเมลยืนยันไม่สำเร็จ: $e')),
      );
    }
  }
}

class _ForbiddenPage extends StatelessWidget {
  const _ForbiddenPage();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Forbidden')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.block, size: 64, color: cs.error),
              const SizedBox(height: 12),
              Text('คุณไม่มีสิทธิ์เข้าถึงหน้านี้',
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 6),
              const Text('ต้องเป็นผู้ดูแลระบบ (admin) เท่านั้น'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('กลับ'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequireVerifyPanel extends StatelessWidget {
  const _RequireVerifyPanel({
    required this.onRefresh,
    required this.onSendVerify,
  });

  final Future<void> Function() onRefresh;
  final Future<void> Function() onSendVerify;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('ต้องยืนยันอีเมล')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.mark_email_unread_outlined, size: 48, color: cs.primary),
                const SizedBox(height: 12),
                Text('โปรดยืนยันอีเมลก่อนใช้งานหน้านี้',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                const Text(
                  'เราส่งอีเมลยืนยันให้ได้ หากยังไม่ได้รับให้กดส่งใหม่ และกดยืนยันในอีเมล จากนั้นกดปุ่มรีเฟรชสถานะ',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onSendVerify,
                        icon: const Icon(Icons.send),
                        label: const Text('ส่งอีเมลยืนยัน'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: onRefresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text('รีเฟรชสถานะ'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
