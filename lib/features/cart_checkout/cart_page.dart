// lib/features/cart_checkout/cart_page.dart
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/app_routes.dart';
import '../../models/game_product.dart';
import '../../services/firestore_service.dart';
import '../../state/cart_provider.dart';

class CartPage extends StatelessWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final fmt = NumberFormat.currency(locale: 'th_TH', symbol: '฿');
    final cs = Theme.of(context).colorScheme;

    final double subtotal = cart.total;
    const double shipping = 0; // เกมดิจิทัล → ส่งฟรี
    const double tax = 0;      // ตัวอย่าง
    final double grandTotal = subtotal + shipping + tax;

    return Scaffold(
      appBar: AppBar(title: const Text('Cart')),
      body: cart.isEmpty
          ? const Center(child: Text('ตะกร้าว่าง'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // รายการสินค้า
                ...cart.items.map((it) {
                  // เรายังต้องการ StreamBuilder เพื่อดึงข้อมูลสต็อก/รูปภาพล่าสุดของ GameProduct หลัก
                  return StreamBuilder<GameProduct?>(
                    stream: FirestoreService.instance.streamProductById(it.productId),
                    builder: (context, snap) {
                      final p = snap.data; // GameProduct หลัก (เพื่อดึงรูป/Variant Info)
                      
                      // 1. ใช้ stock และ price ที่ถูกต้องตาม Variant
                      final int effectiveStock = p?.stockFor(it.variantKey) ?? 0;
                      final double effectivePrice = p?.effectivePriceFor(it.variantKey) ?? it.price;
                      
                      final stock = effectiveStock;
                      final canIncrease = stock > 0 && it.qty < stock;
                      final canDecrease = it.qty > 1;

                      Widget thumb;
                      final img = (p?.images.isNotEmpty == true) ? p!.images.first : null;
                      if (img != null && img.startsWith('http')) {
                        thumb = ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: AspectRatio(
                            aspectRatio: 1,
                            child: Image.network(img, fit: BoxFit.cover),
                          ),
                        );
                      } else {
                        thumb = Container(
                          height: 56,
                          width: 56,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: cs.surfaceContainerHighest.withOpacity(.6),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.image_not_supported),
                        );
                      }
                      
                      // ชื่อ Variant ที่แสดงผล
                      final variantName = p?.getVariant(it.variantKey)?.name;
                      final displayTitle = it.title; // ชื่อสินค้าพร้อม Variant ถูกตั้งใน Service แล้ว

                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // แถวซ้ายรูป + ขวาข้อมูล/ราคา
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SizedBox(height: 56, width: 56, child: thumb),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        displayTitle, // ใช้ Title ที่รวม Variant แล้ว
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context).textTheme.titleMedium,
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          // แสดง Platform หรือ ชื่อ Variant ถ้ามี
                                          Text(
                                              variantName ?? it.platform, 
                                              style: Theme.of(context).textTheme.bodySmall
                                          ),
                                          if (p != null) ...[
                                            const SizedBox(width: 8),
                                            Icon(Icons.inventory_2_outlined, size: 14, color: cs.outline),
                                            const SizedBox(width: 2),
                                            Text('สต๊อก: $stock',
                                                style: Theme.of(context).textTheme.bodySmall),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // ราคาต่อบรรทัด
                                Text(fmt.format(effectivePrice * it.qty),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700)),
                              ],
                            ),

                            const SizedBox(height: 10),

                            // แถวปุ่ม +/– และ Remove
                            Row(
                              children: [
                                // ลด
                                IconButton.filledTonal(
                                  tooltip: 'ลดจำนวน',
                                  onPressed: (!canDecrease || uid == null)
                                      ? null
                                      : () async {
                                          await FirestoreService.instance.changeCartQtyCapped(
                                            uid: uid,
                                            product: p ??
                                                GameProduct(
                                                  id: it.productId,
                                                  title: it.title,
                                                  platform: it.platform,
                                                  region: '',
                                                  price: effectivePrice,
                                                  stock: effectiveStock,
                                                  images: const [],
                                                ),
                                            delta: -1,
                                            variantKey: it.variantKey, // ✅ ส่ง variantKey
                                          );
                                        },
                                  icon: const Icon(Icons.remove),
                                ),
                                const SizedBox(width: 6),
                                Text('${it.qty}',
                                    style: const TextStyle(fontWeight: FontWeight.w700)),
                                const SizedBox(width: 6),
                                // เพิ่ม
                                IconButton.filledTonal(
                                  tooltip: 'เพิ่มจำนวน',
                                  onPressed: (!canIncrease || uid == null)
                                      ? null
                                      : () async {
                                          await FirestoreService.instance.changeCartQtyCapped(
                                            uid: uid,
                                            product: p ??
                                                GameProduct(
                                                  id: it.productId,
                                                  title: it.title,
                                                  platform: it.platform,
                                                  region: '',
                                                  price: effectivePrice,
                                                  stock: effectiveStock,
                                                  images: const [],
                                                ),
                                            delta: 1,
                                            variantKey: it.variantKey, // ✅ ส่ง variantKey
                                          );
                                        },
                                  icon: const Icon(Icons.add),
                                ),

                                const Spacer(),

                                // Remove
                                TextButton.icon(
                                  // 2. ใช้ it.uniqueId ในการลบ
                                  onPressed: uid == null
                                      ? null
                                      : () => context.read<CartProvider>().remove(it.uniqueId),
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  label: const Text('Remove',
                                      style: TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  );
                }).toList(),

                const SizedBox(height: 8),

                // ปุ่มล้างตะกร้า (optional)
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton(
                    onPressed: cart.isEmpty || uid == null
                        ? null
                        : () async => FirestoreService.instance.clearCart(uid),
                    child: const Text('ล้างตะกร้า'),
                  ),
                ),

                const SizedBox(height: 16),

                // กล่องสรุปคำสั่งซื้อ
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      )
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('สรุปคำสั่งซื้อ',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 12),

                      _summaryRow(context, 'ราคาสินค้า', fmt.format(subtotal)),
                      _summaryRow(context, 'ค่าจัดส่ง', 'ฟรี'),
                      _summaryRow(context, 'ภาษี', fmt.format(tax)),
                      const Divider(height: 24),

                      _summaryRow(
                        context,
                        'ยอดรวม',
                        fmt.format(grandTotal),
                        isEmphasis: true,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'ชำระเงินหลังจากสั่งซื้อ',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 12),

                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: cart.isEmpty
                              ? null
                              : () => Navigator.pushNamed(
                                    context, AppRoutes.checkout),
                          child: const Text('ชำระเงิน'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _summaryRow(BuildContext context, String left, String right,
      {bool isEmphasis = false}) {
    final styleBase = Theme.of(context).textTheme.bodyMedium;
    final style = isEmphasis
        ? styleBase?.copyWith(fontWeight: FontWeight.w800)
        : styleBase;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(left, style: style)),
          Text(right, style: style),
        ],
      ),
    );
  }
}