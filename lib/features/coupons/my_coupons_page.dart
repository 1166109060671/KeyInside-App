// lib/features/coupons/my_coupons_page.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:keyinside/app/app_routes.dart'; 
import 'package:keyinside/models/coupon.dart';
import 'package:keyinside/services/firestore_service.dart';

class MyCouponsPage extends StatelessWidget {
  const MyCouponsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('คูปองของฉัน')),
        body: const Center(
          child: Text('กรุณาล็อกอินเพื่อดูคูปองของคุณ'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('คูปองของฉัน'),
      ),
      body: StreamBuilder<List<Coupon>>(
        stream: FirestoreService.instance.streamMyClaimedCoupons(uid), 
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final coupons = snapshot.data ?? [];
          
          // 1. 🚀 [แก้ไข] อัปเกรด Empty State ให้สวยขึ้น
          if (coupons.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.card_giftcard_outlined, 
                      size: 64, 
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'คุณยังไม่มีคูปองที่เก็บไว้', 
                      style: Theme.of(context).textTheme.titleMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'กด "เก็บคูปองเพิ่มเติม" ด้านล่างเพื่อค้นหาคูปองใหม่ๆ',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                    // (เราไม่ต้องใส่ปุ่มตรงนี้ เพราะ FAB จะลอยอยู่แล้ว)
                  ],
                ),
              ),
            );
          }

          // 2. 🚀 [แก้ไข] เพิ่ม Padding ด้านล่าง 80 กัน FAB บัง
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80), 
            itemCount: coupons.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final coupon = coupons[index];
              return _CouponCard(coupon: coupon); 
            },
          );
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(context, AppRoutes.couponDiscover),
        label: const Text('เก็บคูปองเพิ่มเติม'),
      ),
    );
  }
}

// 3. 🚀 [แก้ไข] ออกแบบ _CouponCard ใหม่ทั้งหมด
class _CouponCard extends StatelessWidget {
  const _CouponCard({required this.coupon});
  final Coupon coupon;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bool expired = coupon.isExpired;
    final String expiryText = DateFormat('dd/MM/yyyy').format(coupon.expiryDate.toDate());

    // --- สร้างข้อความส่วนลดให้ชัดเจน ---
    String discountLabel;
    if (coupon.isPercentage) {
      discountLabel = '${coupon.discountValue.toStringAsFixed(0)}%';
    } else {
      discountLabel = '฿${coupon.discountValue.toStringAsFixed(0)}';
    }

    // --- กำหนดสีสำหรับสถานะหมดอายุ ---
    final Color primaryColor = expired ? cs.onSurface.withOpacity(0.5) : cs.primary;
    final Color surfaceColor = expired ? cs.surfaceContainerHighest.withOpacity(0.5) : cs.surfaceContainerHighest;
    final Color onSurfaceColor = expired ? cs.onSurface.withOpacity(0.5) : cs.onSurface;
    final Color offerBgColor = expired ? cs.surfaceContainer.withOpacity(0.5) : cs.surfaceContainer;


    return Card(
      elevation: 0,
      color: surfaceColor, // 👈 ใช้สีที่กำหนด
      clipBehavior: Clip.antiAlias, // 👈 เพิ่ม: เพื่อให้มุมโค้งสวยงาม
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: IntrinsicHeight( // 👈 เพิ่ม: เพื่อให้ Row สูงเท่ากัน
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- ส่วนที่ 1: (ซ้าย) ส่วนลด / ไอคอน ---
            Container(
              width: 100, // 👈 กำหนดความกว้างคงที่
              color: offerBgColor, // 👈 ใช้สีพื้นหลังที่ต่างกันเล็กน้อย
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.local_offer_outlined, 
                    color: primaryColor, 
                    size: 28,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    discountLabel, // 👈 แสดงค่าส่วนลด
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: primaryColor,
                        ),
                  ),
                ],
              ),
            ),

            // --- ส่วนที่ 2: (ขวา) รายละเอียด ---
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      coupon.code, // 👈 แสดงโค้ด
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: onSurfaceColor, // 👈 ใช้สีที่กำหนด
                        ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      coupon.description, // 👈 แสดงคำอธิบาย
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: onSurfaceColor,
                        ),
                    ),
                    const Spacer(), // 👈 ดันข้อความด้านล่างไปล่างสุด
                    const Divider(height: 16),
                    Text(
                      expired
                          ? 'หมดอายุแล้ว'
                          : 'ใช้ได้ถึง: $expiryText (ขั้นต่ำ ฿${coupon.minSpend.toStringAsFixed(0)})',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: expired ? cs.error.withOpacity(0.7) : cs.onSurfaceVariant,
                        ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
