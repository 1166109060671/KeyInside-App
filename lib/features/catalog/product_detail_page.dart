// lib/features/catalog/product_detail_page.dart
import 'dart:convert';
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app/app_routes.dart';
import '../../models/game_product.dart';
import '../../services/firestore_service.dart';

// เปลี่ยนเป็น StatefulWidget เพื่อจัดการสถานะการเลือก Variant และ Quantity
class ProductDetailPage extends StatefulWidget {
  const ProductDetailPage({super.key});

  @override
  State<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends State<ProductDetailPage> {
  // สถานะที่ต้องจัดการ
  String? _selectedVariantKey;
  int _qty = 1;

  // ✅ เพิ่ม: สถานะสำหรับจัดการรูปภาพที่ถูกเลือก
  int _selectedIndex = 0;

  // ✅ เพิ่ม: ตัวแปรสำหรับจัดการ Stream Subscription
  StreamSubscription<GameProduct?>? _productSubscription;
  String? _currentProductId;
  GameProduct? _productData; // เก็บข้อมูล Product ล่าสุดจาก Stream

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _productSubscription?.cancel(); // ยกเลิก Subscription เมื่อ Widget ถูกทำลาย
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final newId = ModalRoute.of(context)?.settings.arguments as String?;
    if (newId != _currentProductId) {
      _productSubscription?.cancel();
      _productData = null;
      _currentProductId = newId;
      _selectedIndex = 0; // รีเซ็ต index รูปภาพเมื่อเปลี่ยนสินค้า

      if (newId != null) {
        _productSubscription =
            FirestoreService.instance.streamProductById(newId).listen((product) {
          if (!mounted) return;

          if (product != null && _selectedVariantKey == null) {
            setState(() {
              // ให้ Build รอบถัดไปเซ็ต qty = 1 โดยเริ่มจาก 0
              _selectedVariantKey = null;
              _qty = 0;
            });
          }

          setState(() {
            _productData = product;
          });
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = ModalRoute.of(context)?.settings.arguments as String?;
    if (id == null) {
      return const Scaffold(body: Center(child: Text('ไม่พบสินค้า')));
    }

    final fmt = NumberFormat.currency(locale: 'th_TH', symbol: '฿');

    final p = _productData;
    if (p == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 1. คำนวณราคาและสต็อกตาม Variant ที่ถูกเลือก (หรือใช้ Base)
    final double effectivePrice = p.effectivePriceFor(_selectedVariantKey);
    final int effectiveStock = p.stockFor(_selectedVariantKey);
    final bool isOutOfStock = effectiveStock == 0;

    // 2. ปรับ quantity ให้ไม่เกิน stock
    if (_qty > effectiveStock) {
      _qty = effectiveStock.clamp(1, effectiveStock);
    }
    if (_qty == 0 && effectiveStock > 0) {
      _qty = 1;
    }

    // =======================================================
    // UI
    // =======================================================
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('Keys Inside'),
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_cart),
            onPressed: () => Navigator.pushNamed(context, AppRoutes.cart),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ---------- รูปหลัก + แถบรูปเล็ก ----------
          StatefulBuilder(
            builder: (context, setInnerState) {
              final hasImages = p.images.isNotEmpty;
              final String? bigUrl = (hasImages && _selectedIndex < p.images.length)
                  ? p.images[_selectedIndex]
                  : null;

              final bigImage = AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (bigUrl != null)
                        _buildImage(bigUrl)
                      else
                        Container(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withOpacity(.5),
                          child: const Center(child: Icon(Icons.image_not_supported)),
                        ),
                      if (p.isLowStock && !isOutOfStock)
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.red.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              'เหลือ $effectiveStock key',
                              style:
                                  const TextStyle(color: Colors.white, fontSize: 12),
                            ),
                          ),
                        ),
                      if (isOutOfStock)
                        Container(
                          color: Colors.black.withOpacity(0.55),
                          child: const Center(
                            child: Text(
                              'สินค้าหมด',
                              style:
                                  TextStyle(color: Colors.white, fontSize: 22),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // รูปใหญ่
                  bigImage,
                  const SizedBox(height: 10),

                  
                  // ✅ แถบรูปเล็กเลือกเปลี่ยนรูปหลัก (ทำให้พอดีเท่ากันทุกอัน)
if (p.images.length > 1)
  SizedBox(
    height: 82, // สูงพอดีกับกล่อง 78 + เส้นขอบ/เงา
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      itemCount: p.images.length.clamp(0, 10),
      separatorBuilder: (_, __) => const SizedBox(width: 10),
      itemBuilder: (context, i) {
        final url = p.images[i];
        final isSelected = i == _selectedIndex;

        return GestureDetector(
          onTap: () {
            if (mounted) setInnerState(() => _selectedIndex = i);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            width: 118,
            height: 78,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: Colors.black12,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                width: isSelected ? 2 : 1,
                color: isSelected
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context)
                        .colorScheme
                        .outlineVariant
                        .withOpacity(.6),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: AspectRatio(
                aspectRatio: 1, // บังคับเป็นสี่เหลี่ยมจัตุรัส
                child: _buildImage(url), // ภายใน _buildImage ใช้ BoxFit.cover อยู่แล้ว
              ),
            ),
          ),
        );
      },
    ),
  ),

          const SizedBox(height: 16),

          // ---------- ชื่อ/แท็ก/ราคา ----------
          Text(p.title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              Chip(label: Text(p.platform)),
              Chip(label: Text(p.region)),
              const Chip(label: Text('Digital Delivery')),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            fmt.format(effectivePrice),
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),

          // ---------- ตัวเลือกย่อย (Variants) ----------
          if (p.hasVariants) ...[
            const Text('ตัวเลือกสินค้า',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                // ✅ 1) ตัวเลือก Standard (Base Product)
                ChoiceChip(
                  label: const Text('Standard Edition'),
                  selected: _selectedVariantKey == null,
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _selectedVariantKey = null; // Base
                        _qty = 0; // ให้ Build รอบถัดไปเซ็ตเป็น 1
                      });
                    }
                  },
                ),
                // ✅ 2) แสดง Variants ที่เหลือจาก p.variants
                ...p.variants.values.map((v) {
                  final isSelected = v.key == _selectedVariantKey;
                  return ChoiceChip(
                    label: Text(v.name),
                    selected: isSelected,
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _selectedVariantKey = v.key;
                          _qty = 0;
                        });
                      }
                    },
                  );
                }).toList(),
              ],
            ),
            const SizedBox(height: 16),
          ],

          const Text(
            'รายละเอียด:\n• รับคีย์เกมหลังชำระเงินสำเร็จ\n• ตรวจสอบ Platform/Region ให้ถูกต้อง\n• แนบวิธี Redeem พร้อมคีย์',
          ),
          const SizedBox(height: 16),

          // ---------- จำนวน ----------
          Row(
            children: [
              const Text('จำนวน', style: TextStyle(fontWeight: FontWeight.w600)),
              IconButton(
                onPressed: (isOutOfStock || _qty <= 1)
                    ? null
                    : () => setState(() => _qty--),
                icon: const Icon(Icons.remove),
              ),
              Text('$_qty', style: const TextStyle(fontWeight: FontWeight.w700)),
              IconButton(
                onPressed: isOutOfStock
                    ? null
                    : () {
                        if (_qty < effectiveStock) {
                          setState(() => _qty++);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('เกินจำนวนสต๊อกที่มี')),
                          );
                        }
                      },
                icon: const Icon(Icons.add),
              ),
              const Spacer(),
              if (!isOutOfStock)
                Text('สต๊อก: $effectiveStock',
                    style: const TextStyle(fontSize: 12)),
            ],
          ),
          const SizedBox(height: 16),

          // ---------- ปุ่มเพิ่มลงตะกร้า ----------
          FilledButton.icon(
            onPressed: isOutOfStock
                ? null
                : () async {
                    final user = FirebaseAuth.instance.currentUser;
                    if (user == null) {
                      // ส่งกลับมาที่สินค้าตัวเดิมหลังล็อกอินสำเร็จ
                      Navigator.pushNamed(
                        context,
                        AppRoutes.login,
                        arguments: {
                          'redirectTo': AppRoutes.productDetail,
                          'redirectArgs': id,
                        },
                      );
                      return;
                    }

                    final VariantOption? selectedVariant =
                        p.getVariant(_selectedVariantKey);
                    final displayVariantName =
                        _selectedVariantKey == null ? 'Standard' : selectedVariant?.name;

                    try {
                      await FirestoreService.instance.addToCartCapped(
                        uid: user.uid,
                        product: p,
                        addQty: _qty,
                        variantKey: _selectedVariantKey, // null สำหรับ Standard
                      );
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'เพิ่ม ${p.title} (${displayVariantName ?? ''}) x$_qty ลงในตะกร้าแล้ว'),
                          action: SnackBarAction(
                            label: 'ดูตะกร้า',
                            onPressed: () =>
                                Navigator.pushNamed(context, AppRoutes.cart),
                          ),
                        ),
                      );
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('เพิ่มลงตะกร้าไม่สำเร็จ: $e')),
                      );
                    }
                  },
            icon: const Icon(Icons.add_shopping_cart),
            label: Text(isOutOfStock ? 'สินค้าหมด' : 'เพิ่มลงตะกร้า'),
          ),

          const Divider(height: 32),
          const ListTile(
            leading: Icon(Icons.help_outline),
            title: Text('วิธีรับคีย์'),
            subtitle:
                Text('หลังชำระสำเร็จจะได้รับคีย์ใน “คำสั่งซื้อของฉัน” และทางอีเมล'),
          ),
          const ListTile(
            leading: Icon(Icons.verified_user_outlined),
            title: Text('ความปลอดภัยในการชำระเงิน'),
            subtitle: Text('คีย์จะถูกปล่อยหลังผู้ให้บริการชำระเงินยืนยันเท่านั้น'),
          ),
        ],
      );
  })]));
  }
}

///
/// ตัวช่วยโหลดรูป: รองรับทั้ง URL และ Base64 (data:image/*;base64,...)
///
Widget _buildImage(String imageUrl) {
  if (imageUrl.startsWith('http')) {
    // ถ้าเป็น URL ให้โหลดภาพจาก URL
    return Image.network(
      imageUrl,
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) {
        return const Center(child: Icon(Icons.broken_image));
      },
    );
  } else if (imageUrl.startsWith('data:image')) {
    // ถ้าเป็น base64 ให้แปลงจาก Base64
    try {
      final bytes = base64Decode(imageUrl.split(',').last); // ตัด prefix ออก
      return Image.memory(
        bytes,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return const Center(child: Icon(Icons.broken_image));
        },
      );
    } catch (e) {
      return const Center(child: Icon(Icons.broken_image)); // base64 ผิดพลาด
    }
  } else {
    // ไม่ใช่ URL หรือ base64
    return const Center(child: Icon(Icons.image_not_supported));
  }
}
