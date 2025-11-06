// lib/features/coupons/coupon_discover_page.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:project_android/models/coupon.dart';
import 'package:project_android/services/firestore_service.dart';

class CouponDiscoverPage extends StatelessWidget {
  const CouponDiscoverPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(
        appBar: null,
        body: Center(child: Text('กรุณาล็อกอินเพื่อกดรับคูปอง')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('คูปองที่มีให้เก็บ')),
      body: StreamBuilder<List<Coupon>>(
        // 1. ดึงคูปอง "ส่วนกลาง" ทั้งหมดที่ยังไม่หมดอายุ
        stream: FirestoreService.instance.streamCoupons(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final coupons = snapshot.data ?? [];
          if (coupons.isEmpty) {
            return const Center(child: Text('ไม่มีคูปองให้เก็บในขณะนี้'));
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: coupons.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final coupon = coupons[index];
              // 2. ส่ง uid และ coupon ไปให้ Card จัดการสถานะ "กดรับ"
              return _ClaimableCouponCard(coupon: coupon, uid: uid);
            },
          );
        },
      ),
    );
  }
}

/// ---
/// การ์ดคูปองที่เช็คสถานะ "รับแล้ว" ได้เอง (Self-managing state)
/// ---
class _ClaimableCouponCard extends StatefulWidget {
  const _ClaimableCouponCard({
    required this.coupon,
    required this.uid,
  });
  final Coupon coupon;
  final String uid;

  @override
  State<_ClaimableCouponCard> createState() => _ClaimableCouponCardState();
}

class _ClaimableCouponCardState extends State<_ClaimableCouponCard> {
  bool _isLoading = false;

  /// ฟังก์ชันสำหรับกดรับ
  Future<void> _claim() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      await FirestoreService.instance.claimCoupon(widget.uid, widget.coupon);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('รับคูปอง "${widget.coupon.code}" แล้ว!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final String expiryText =
        DateFormat('dd/MM/yyyy').format(widget.coupon.expiryDate.toDate());

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.coupon.code,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.coupon.description,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const Divider(height: 20),
            Row(
              children: [
                // --- สถานะ (ยอดขั้นต่ำ + วันหมดอายุ) ---
                Expanded(
                  child: Text(
                    'ใช้ได้ถึง: $expiryText\n(ขั้นต่ำ ฿${widget.coupon.minSpend.toStringAsFixed(0)})',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
                const SizedBox(width: 8),

                // --- ปุ่มกดรับ (เช็คสถานะ Real-time) ---
                StreamBuilder<DocumentSnapshot>(
                  // 3. ฟัง "กระเป๋า" ของเราแบบ Real-time
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(widget.uid)
                      .collection('my_coupons')
                      .doc(widget.coupon.id) // 👈 ฟังที่ ID นี้โดยตรง
                      .snapshots(),
                  builder: (context, snapshot) {
                    final bool isClaimed = snapshot.data?.exists ?? false;

                    if (isClaimed) {
                      return const OutlinedButton(
                        onPressed: null,
                        child: Text('รับแล้ว'),
                      );
                    }

                    if (_isLoading) {
                      return const FilledButton(
                        onPressed: null,
                        child: SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    }

                    return FilledButton(
                      onPressed: _claim,
                      child: const Text('กดรับ'),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
