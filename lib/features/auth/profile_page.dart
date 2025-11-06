import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';

import '../../app/app_routes.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  User? get _user => FirebaseAuth.instance.currentUser;

  bool _busyAvatar = false;

  String _initials(User? u) {
    final name = u?.displayName?.trim();
    if (name != null && name.isNotEmpty) return name.substring(0, 1).toUpperCase();
    final mail = u?.email?.trim();
    if (mail != null && mail.isNotEmpty) return mail.substring(0, 1).toUpperCase();
    return '?';
  }

  Future<void> _logout() async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.catalogList, (r) => false);
  }

  Future<void> _sendVerifyEmail() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await user.sendEmailVerification();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ส่งอีเมลยืนยันแล้ว กรุณาเช็คกล่องจดหมาย/สแปม')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ส่งอีเมลยืนยันไม่สำเร็จ: $e')),
      );
    }
  }

  Future<void> _refreshVerified() async {
    try {
      await FirebaseAuth.instance.currentUser?.reload();
    } catch (_) {}
    if (!mounted) return;
    setState(() {});
    final v = FirebaseAuth.instance.currentUser?.emailVerified ?? false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(v ? 'ยืนยันอีเมลแล้ว' : 'ยังไม่ได้ยืนยันอีเมล')),
    );
  }

  Future<void> _editDisplayName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final controller = TextEditingController(text: user.displayName ?? '');
    final formKey = GlobalKey<FormState>();

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('แก้ไขชื่อที่ใช้แสดง'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Display name',
              border: OutlineInputBorder(),
            ),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'กรุณากรอกชื่อ' : null,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () async {
              if (formKey.currentState?.validate() != true) return;
              try {
                final newName = controller.text.trim();
                await user.updateDisplayName(newName);
                await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
                  {
                    'displayName': newName,
                    'updatedAt': FieldValue.serverTimestamp(),
                  },
                  SetOptions(merge: true),
                );
                try {
                  await FirebaseAuth.instance.currentUser?.reload();
                } catch (_) {}
                if (!mounted) return;
                setState(() {});
                Navigator.pop(context, true);
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')),
                );
              }
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );

    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('อัปเดตชื่อเรียบร้อย')),
      );
    }
  }

  Future<void> _sendResetPassword() async {
    final email = _user?.email;
    if (email == null) return;
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ส่งอีเมลรีเซ็ตรหัสผ่านแล้ว')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ส่งรีเซ็ตไม่สำเร็จ: $e')),
      );
    }
  }

  // -------------------- Avatar (Base64 + Firestore) --------------------

  /// เลือกรูป → ครอปสี่เหลี่ยมจัตุรัส → เก็บเป็น data URL (base64) ใน /users/{uid}
  Future<void> _pickAndSaveAvatar() async {
    final user = _user;
    if (user == null) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 2048,
      imageQuality: 95,
    );
    if (picked == null) return;

    setState(() => _busyAvatar = true);
    try {
      // บันทึกชั่วคราวเพื่อหลบ content://
      final tmpDir = await getTemporaryDirectory();
      final srcPath = '${tmpDir.path}/avatar_src_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final srcFile = File(srcPath);
      await srcFile.writeAsBytes(await picked.readAsBytes(), flush: true);

      // ครอป
      final CroppedFile? cropped = await ImageCropper().cropImage(
        sourcePath: srcFile.path,
        maxWidth: 1024,
        compressQuality: 90,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'ครอปรูปโปรไฟล์',
            toolbarColor: Colors.deepPurple,
            toolbarWidgetColor: Colors.white,
            activeControlsWidgetColor: Colors.deepPurple,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
            hideBottomControls: true,
          ),
          IOSUiSettings(
            title: 'Crop Profile Photo',
            aspectRatioLockEnabled: true,
          ),
        ],
      );

      if (cropped == null) {
        if (mounted) setState(() => _busyAvatar = false);
        return;
      }

      final bytes = await File(cropped.path).readAsBytes();
      final mime = _guessMime(cropped.path);
      final b64 = base64Encode(bytes);
      final dataUrl = 'data:$mime;base64,$b64';

      await user.updatePhotoURL(null);
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {
          'photoB64': dataUrl,
          'photoMime': mime,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      try {
        await user.reload();
      } catch (_) {}

      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('อัปเดตรูปโปรไฟล์เรียบร้อย')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('อัปโหลดรูปไม่สำเร็จ: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyAvatar = false);
    }
  }

  /// ลบรูป (ยืนยันก่อน) + แสดงพรีวิว
  Future<void> _removeAvatar() async {
    final user = _user;
    if (user == null) return;

    Uint8List? previewBytes;
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final dataUrl = doc.data()?['photoB64'] as String?;
      previewBytes = _bytesFromDataUrl(dataUrl);
    } catch (_) {}

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('ยืนยันการลบรูปโปรไฟล์'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (previewBytes != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(48),
                child: Image.memory(previewBytes, height: 96, width: 96, fit: BoxFit.cover),
              ),
              const SizedBox(height: 12),
            ],
            const Text('คุณแน่ใจหรือไม่ว่าต้องการลบรูปโปรไฟล์นี้?\nการลบไม่สามารถย้อนกลับได้'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ลบรูป', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _busyAvatar = true);
    try {
      await user.updatePhotoURL(null);
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set(
        {
          'photoB64': FieldValue.delete(),
          'photoMime': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      try {
        await user.reload();
      } catch (_) {}
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ลบรูปโปรไฟล์แล้ว')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ลบรูปไม่สำเร็จ: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyAvatar = false);
    }
  }

  String _guessMime(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Uint8List? _bytesFromDataUrl(String? dataUrl) {
    if (dataUrl == null || dataUrl.isEmpty) return null;
    final idx = dataUrl.indexOf('base64,');
    final raw = idx >= 0 ? dataUrl.substring(idx + 7) : dataUrl;
    try {
      return base64Decode(raw);
    } catch (_) {
      return null;
    }
  }

  // -------------------- UI --------------------

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    final Stream<DocumentSnapshot<Map<String, dynamic>>>? userDocStream =
        (user == null)
            ? null
            : FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots();

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: userDocStream,
        builder: (context, snap) {
          final map = (snap.data?.data() ?? const <String, dynamic>{});
          final photoDataUrl = (map['photoB64'] as String?);
          final avatarBytes = _bytesFromDataUrl(photoDataUrl);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Header card + menu
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
                  child: Stack(
                    children: [
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Stack(
                              alignment: Alignment.center,
                              children: [
                                CircleAvatar(
                                  radius: 50,
                                  backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                                  backgroundImage:
                                      (avatarBytes != null) ? MemoryImage(avatarBytes) : null,
                                  child: (avatarBytes == null)
                                      ? Text(
                                          _initials(user),
                                          style: const TextStyle(
                                            fontSize: 34,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        )
                                      : null,
                                ),
                                if (_busyAvatar)
                                  const Positioned.fill(
                                    child: Center(
                                      child: SizedBox(
                                        height: 34,
                                        width: 34,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              user?.displayName?.trim().isNotEmpty == true
                                  ? user!.displayName!
                                  : '(ยังไม่ได้ตั้งชื่อ)',
                              style: Theme.of(context).textTheme.titleLarge,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              user?.email ?? '-',
                              style: Theme.of(context).textTheme.bodyMedium,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 8),
                            _StatusPill(
                              text: (user?.emailVerified ?? false)
                                  ? 'Email verified'
                                  : 'Email not verified',
                              positive: user?.emailVerified ?? false,
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        right: 4,
                        top: 4,
                        child: PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert),
                          onSelected: (value) async {
                            if (value == 'change') {
                              await _pickAndSaveAvatar();
                            } else if (value == 'delete') {
                              await _removeAvatar();
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'change',
                              child: Row(
                                children: [
                                  Icon(Icons.photo_camera_outlined, size: 20),
                                  SizedBox(width: 8),
                                  Text('เปลี่ยนรูป'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete_outline, size: 20, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('ลบรูป', style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Email verify prompt
              if (!(user?.emailVerified ?? true)) ...[
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ยืนยันอีเมลของคุณ', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text(
                          'ยืนยันอีเมลเพื่อความปลอดภัยและใช้งานฟีเจอร์สำคัญได้ครบถ้วน',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _sendVerifyEmail,
                                icon: const Icon(Icons.mark_email_unread_outlined),
                                label: const Text('ส่งอีเมลยืนยัน'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _refreshVerified,
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
                const SizedBox(height: 16),
              ],

              // Account management
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.badge_outlined),
                      title: const Text('แก้ไขชื่อที่ใช้แสดง'),
                      subtitle: Text(user?.displayName ?? '(ยังไม่ได้ตั้งชื่อ)'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _editDisplayName,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.lock_reset),
                      title: const Text('รีเซ็ตรหัสผ่านผ่านอีเมล'),
                      subtitle: Text(user?.email ?? '-'),
                      trailing: const Icon(Icons.open_in_new),
                      onTap: _sendResetPassword,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.logout, color: Colors.red),
                      title: const Text('ออกจากระบบ'),
                      onTap: _logout,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Summary tiles
              Row(
                children: [
                  Expanded(
                    child: _SummaryTile(
                      title: 'คำสั่งซื้อ',
                      icon: Icons.receipt_long,
                      onTap: () => Navigator.pushNamed(context, AppRoutes.myOrders),
                    ),
                  ),
                  const SizedBox(width: 12),
                  
                  // 👇 --- [START] แก้ไขส่วนนี้ --- 👇
                  Expanded(
                    child: _SummaryTile(
                      title: 'คูปอง', // 1. เปลี่ยนชื่อ
                      icon: Icons.local_offer_outlined, // 3. เปลี่ยนไอคอน
                      onTap: () => Navigator.pushNamed(context, AppRoutes.myCoupons), // 4. เปลี่ยนที่หมาย
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

// ---------- UI helpers ----------
class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.text, this.positive});
  final String text;
  final bool? positive;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = positive == null
        ? cs.surfaceContainerHighest
        : (positive! ? cs.secondaryContainer : cs.surfaceContainerHighest);
    final fg = positive == null
        ? cs.onSurface
        : (positive! ? cs.onSecondaryContainer : cs.onSurfaceVariant);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(text, style: TextStyle(color: fg)),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.title,
    // ignore: unused_element_parameter
    this.value,
    required this.icon,
    this.onTap,
  });

  final String title;
  final String? value;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          // 1. (แนะนำ) กำหนดให้ Row จัดกลางในแนวตั้ง
          //    เผื่อในอนาคตมีอันไหนสูงไม่เท่ากัน
          crossAxisAlignment: CrossAxisAlignment.center, 
          children: [
            CircleAvatar(
              backgroundColor: cs.primaryContainer,
              child: Icon(icon, color: cs.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                
                // 👇 --- [เพิ่ม/แก้ไข บรรทัดนี้] --- 👇
                mainAxisAlignment: MainAxisAlignment.center, // 2. จัดกลางแนวตั้ง
                // 👆 --- [สิ้นสุดส่วนที่แก้ไข] --- 👆
                
                children: [
                  Text(title, style: Theme.of(context).textTheme.bodySmall),
                  if (value != null)
                    Text(value!, style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
            ),
            if (onTap != null) Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
