import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../app/app_routes.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();

  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pwdCtrl.dispose();
    super.dispose();
  }

  String _errorTextFrom(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'รูปแบบอีเมลไม่ถูกต้อง';
      case 'user-disabled':
        return 'บัญชีนี้ถูกปิดใช้งาน';
      case 'user-not-found':
        return 'ไม่พบบัญชีผู้ใช้นี้';
      case 'wrong-password':
        return 'อีเมลหรือรหัสผ่านไม่ถูกต้อง';
      case 'too-many-requests':
        return 'พยายามมากเกินไป โปรดลองใหม่ภายหลัง';
      default:
        return e.message ?? 'เข้าสู่ระบบไม่สำเร็จ';
    }
  }

  Future<void> _login() async {
    if (_loading) return;
    if (_formKey.currentState?.validate() != true) return;

    setState(() => _loading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailCtrl.text.trim(),
        password: _pwdCtrl.text.trim(),
      );

      if (!mounted) return;

      // รองรับ redirect กลับไปยังหน้าที่ถูกบล็อกโดย AuthGuard
      final args = ModalRoute.of(context)?.settings.arguments;
      String redirectTo = AppRoutes.catalogList;
      Object? redirectArgs;

      if (args is Map) {
        final map = Map<String, dynamic>.from(args);
        if (map['redirectTo'] is String && (map['redirectTo'] as String).isNotEmpty) {
          redirectTo = map['redirectTo'] as String;
          redirectArgs = map['arguments'];
        }
      }

      Navigator.of(context).pushNamedAndRemoveUntil(
        redirectTo,
        (route) => false,
        arguments: redirectArgs,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_errorTextFrom(e))));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('เกิดข้อผิดพลาด: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('กรอกอีเมลก่อนรีเซ็ตรหัสผ่าน')),
      );
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ส่งอีเมลรีเซ็ตรหัสผ่านแล้ว')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ไม่สามารถส่งได้: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(14));

    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            elevation: 1,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: cs.primaryContainer,
                        child: Icon(Icons.lock_open, color: cs.onPrimaryContainer),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('เข้าสู่ระบบ', style: Theme.of(context).textTheme.titleLarge),
                          Text('กรอกรายละเอียดบัญชีของคุณ',
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Form
                  Form(
                    key: _formKey,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _emailCtrl,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          decoration: InputDecoration(
                            labelText: 'Email',
                            prefixIcon: const Icon(Icons.alternate_email),
                            border: border,
                          ),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? 'กรอกอีเมล' : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _pwdCtrl,
                          obscureText: _obscure,
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _login(),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              onPressed: () => setState(() => _obscure = !_obscure),
                              icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                            ),
                            border: border,
                          ),
                          validator: (v) =>
                              (v != null && v.length >= 6) ? null : 'รหัสผ่านอย่างน้อย 6 ตัว',
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            icon: const Icon(Icons.mail_lock, size: 18),
                            onPressed: _loading ? null : _forgotPassword,
                            label: const Text('ลืมรหัสผ่าน'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: _loading
                              ? const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(12),
                                    child: CircularProgressIndicator(),
                                  ),
                                )
                              : FilledButton(
                                  onPressed: _login,
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                  child: const Text('Login'),
                                ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text('ยังไม่มีบัญชี?'),
                            TextButton(
                              onPressed:
                                  _loading ? null : () => Navigator.pushNamed(context, AppRoutes.signup),
                              child: const Text('สมัครสมาชิก'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Tips / Info
          const SizedBox(height: 16),
          Row(
            children: const [
              Expanded(
                child: _InfoTile(
                  icon: Icons.security,
                  title: 'ปลอดภัย',
                  subtitle: 'ข้อมูลของคุณถูกเข้ารหัส',
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: _InfoTile(
                  icon: Icons.support_agent,
                  title: 'ช่วยเหลือ',
                  subtitle: 'ติดต่อร้านได้ตลอด',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: cs.secondaryContainer,
            child: Icon(icon, color: cs.onSecondaryContainer),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
