// lib/features/cart_checkout/checkout_page.dart

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart'; // 👈 [1. เพิ่ม] Import Auth
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import '../../models/coupon.dart';
import '../../services/firestore_service.dart';
import '../../state/cart_provider.dart';


class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key});
  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtl = TextEditingController();
  final _emailCtl = TextEditingController();
  final _noteCtl = TextEditingController();
  bool _submitting = false;

  Coupon? _appliedCoupon;
  double _discountAmount = 0.0;

  @override
  void initState() {
    super.initState();
    final user = FirebaseAuth.instance.currentUser;
    _nameCtl.text = user?.displayName ?? '';
    _emailCtl.text = user?.email ?? '';
  }

  @override
  void dispose() {
    _nameCtl.dispose();
    _emailCtl.dispose();
    _noteCtl.dispose();
    super.dispose();
  }

  Future<void> _selectCoupon() async {
    final cart = context.read<CartProvider>();
    final subtotal = cart.total;

    final Coupon? selectedCoupon = await showModalBottomSheet<Coupon?>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) => _CouponSelectionSheet(subtotal: subtotal),
    );

    if (selectedCoupon == null) {
      setState(() {
        _appliedCoupon = null;
        _discountAmount = 0;
      });
    } else {
      final discount = selectedCoupon.calculateDiscount(subtotal);
      setState(() {
        _appliedCoupon = selectedCoupon;
        _discountAmount = discount;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final cs = Theme.of(context).colorScheme;

    final double subtotal = cart.total;
    final double grandTotal = (subtotal - _discountAmount).clamp(0, subtotal);

    return Scaffold(
      // ... (โค้ดส่วน UI ของ CheckoutPage เหมือนเดิมทุกประการ) ...
      // ... (Card สรุปรายการ) ...
      // ... (Card ข้อมูลผู้ซื้อ) ...
      // ... (BottomNavigationBar) ...
      appBar: AppBar(title: const Text('Checkout')),
      body: cart.isEmpty
          ? const Center(child: Text('ตะกร้าของคุณว่างเปล่า'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('สรุปรายการ',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        ...cart.items.map(
                          (it) => ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(it.title),
                            subtitle: Text('${it.platform} • x${it.qty}'),
                            trailing: Text(
                                '฿ ${(it.price * it.qty).toStringAsFixed(2)}'),
                          ),
                        ),
                        const Divider(),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          leading: Icon(Icons.local_offer_outlined, color: cs.primary),
                          title: const Text('ส่วนลด'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_appliedCoupon != null)
                                Text(
                                  _appliedCoupon!.code,
                                  style: TextStyle(color: cs.primary, fontWeight: FontWeight.bold),
                                ),
                              if (_appliedCoupon == null)
                                const Text('เลือกคูปอง'),
                              const SizedBox(width: 4),
                              Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                            ],
                          ),
                          onTap: _selectCoupon,
                        ),
                        Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 4),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('ยอดรวมตะกร้า'),
                              Text('฿ ${subtotal.toStringAsFixed(2)}'),
                            ],
                          ),
                        ),
                        if (_appliedCoupon != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('ส่วนลด (${_appliedCoupon!.code})',
                                    style: TextStyle(color: cs.primary)),
                                Text('- ฿ ${_discountAmount.toStringAsFixed(2)}',
                                    style: TextStyle(
                                        color: cs.primary,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        const Divider(),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'ยอดสุทธิ: ฿ ${grandTotal.toStringAsFixed(2)}',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ข้อมูลผู้ซื้อ',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _nameCtl,
                            decoration: const InputDecoration(
                              labelText: 'ชื่อสำหรับติดต่อ',
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) =>
                                (v == null || v.trim().isEmpty) ? 'กรอกชื่อ' : null,
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _emailCtl,
                            keyboardType: TextInputType.emailAddress,
                            decoration: const InputDecoration(
                              labelText: 'อีเมลสำหรับรับคีย์',
                              border: OutlineInputBorder(),
                            ),
                            validator: (v) =>
                                (v == null || v.trim().isEmpty) ? 'กรอกอีเมล' : null,
                          ),
                          TextFormField(
                            controller: _noteCtl,
                            maxLines: 2,
                            decoration: const InputDecoration(
                              labelText: 'หมายเหตุ (ถ้ามี)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 120),
              ],
            ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.all(16),
        child: FilledButton(
          onPressed: (_submitting || cart.isEmpty)
              ? null
              : () async {
                  final proof = await _openPaymentProofSheet(
                    context,
                    amount: grandTotal, 
                  );
                  if (proof == null) return;
                  await _submitWithProof(
                    proof,
                    subtotal,
                    _appliedCoupon,
                    _discountAmount,
                  );
                },
          child: _submitting
              ? const Padding(
                  padding: EdgeInsets.all(6),
                  child: SizedBox(
                    height: 22,
                    width: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : const Text('ยืนยันสั่งซื้อ'),
        ),
      ),
    );
  }

  Future<void> _submitWithProof(
    _PaymentProofResult proof,
    double subtotal,
    Coupon? coupon,
    double discount,
  ) async {
    // ... (โค้ดส่วน _submitWithProof เหมือนเดิม) ...
    if (_submitting) return;
    if (_formKey.currentState?.validate() != true) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('กรุณาเข้าสู่ระบบก่อนทำรายการ')));
      return;
    }
    Coupon? verifiedCoupon = coupon;
    double verifiedDiscount = discount;

    if (coupon != null) {
  try {
    final ok = await FirestoreService.instance
        .validateCoupon(user.uid, coupon.code, subtotal);
    verifiedCoupon = ok; // ใช้ตัวที่ผ่าน validate แล้ว
    verifiedDiscount = ok.calculateDiscount(subtotal);
  } catch (e) {
    // ถ้า validate ไม่ผ่าน ให้ล้างคูปองทิ้ง และแจ้งเตือน
    verifiedCoupon = null;
    verifiedDiscount = 0;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('คูปองใช้ไม่ได้: $e')),
      );
    }
  }
}


    setState(() => _submitting = true);
    try {
      final orderId = await FirestoreService.instance.createOrder(
        uid: user.uid,
        paymentMethod: proof.channel,
        buyerName: _nameCtl.text.trim(),
        email: _emailCtl.text.trim(),
        note: _noteCtl.text.trim(),
        subtotal: subtotal,
        couponCode: verifiedCoupon?.code,
        discount: verifiedDiscount,
      );

      final bytes = await proof.file.readAsBytes();
      final base64Img = base64Encode(bytes);

      await FirebaseFirestore.instance.collection('orders').doc(orderId).set({
        'paymentProofBase64': base64Img,
        'paymentChannel': proof.channel,
        'paymentProofUploadedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final cart = context.read<CartProvider>();
      await FirestoreService.instance.clearCart(user.uid);
      cart.clear();

      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('สั่งซื้อสำเร็จ 🎉'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('เราได้รับคำสั่งซื้อของคุณแล้ว'),
              SizedBox(height: 8),
              Text('แอดมินจะตรวจสอบหลักฐานและปล่อยคีย์ให้เร็วที่สุด'),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ตกลง'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.pop(context); 
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('ทำรายการไม่สำเร็จ: $e')));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

// ... (โค้ดส่วน _PaymentProofSheet และ Helpers เหมือนเดิม) ...
class PaymentChannels {
  static const bank = 'BankTransfer';
  static const promptpay = 'PromptPay';
}
class PayAccountInfo {
  final String label;
  final String title;
  final List<List<String>> rows;
  const PayAccountInfo(this.label, this.title, this.rows);
}
const kBankInfo = PayAccountInfo(
  'ธ.ไทยพาณิชย์',
  'บัญชีไทยพาณิชย์',
  [
    ['ชื่อบัญชี', 'นายวันชาติ อยู่ยืน'],
    ['เลขบัญชี', '2482495970'],
    ['ธนาคาร', 'Thai Panich Bank (SCB)'],
  ],
);
const kPromptPayInfo = PayAccountInfo(
  'PromptPay',
  'พร้อมเพย์',
  [
    ['หมายเลข', '0626692482'],
    ['ชื่อ', 'คุณวันชาติ อยู่ยืน'],
  ],
);
class _PaymentProofResult {
  final String channel;
  final XFile file;
  _PaymentProofResult(this.channel, this.file);
}
Future<_PaymentProofResult?> _openPaymentProofSheet(
  BuildContext context, {
  required double amount,
}) {
  return showModalBottomSheet<_PaymentProofResult>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => _PaymentProofSheet(amount: amount),
  );
}
class _PaymentProofSheet extends StatefulWidget {
  const _PaymentProofSheet({required this.amount});
  final double amount;

  @override
  State<_PaymentProofSheet> createState() => _PaymentProofSheetState();
}
class _PaymentProofSheetState extends State<_PaymentProofSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);
  XFile? _file;
  bool _submitting = false; 

  String get _channel {
    switch (_tab.index) {
      case 0:
        return PaymentChannels.bank;
      case 1:
        return PaymentChannels.promptpay;
      default:
        return PaymentChannels.bank;
    }
  }

  Future<void> _pick() async {
    if (_submitting) return;
    setState(() => _submitting = true);

    try {
      final picker = ImagePicker();
      final img = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 80,
      );
      if (img == null) {
        if (mounted) setState(() => _submitting = false);
        return;
      }

      final len = await img.length();
      if (len > 1 * 1024 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('ไฟล์ใหญ่เกิน 1MB')));
        if (mounted) setState(() => _submitting = false);
        return;
      }
      setState(() => _file = img);
    } catch (e) {
      debugPrint("Error picking image: $e");
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _infoCard(PayAccountInfo info) {
    final cs = Theme.of(context).colorScheme;

    String _extractMainNumber(List<List<String>> rows) {
      for (final r in rows) {
        final label = r[0];
        if (label.contains('เลขบัญชี') || label.contains('หมายเลข')) {
          return r[1];
        }
      }
      return rows.first[1];
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(info.title,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                tooltip: 'คัดลอกเลขบัญชี / หมายเลข',
                onPressed: () {
                  final number = _extractMainNumber(info.rows);
                  Clipboard.setData(ClipboardData(text: number));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('คัดลอก: $number')),
                  );
                },
                icon: const Icon(Icons.copy_outlined),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...info.rows.map(
            (r) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      r[0],
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  Text(r[1],
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Text('อัปโหลดหลักฐานการชำระเงิน',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'ยอดที่ต้องชำระ: ฿${widget.amount.toStringAsFixed(2)}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withOpacity(.5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TabBar(
              controller: _tab,
              tabs: const [
                Tab(text: 'ธนาคารไทยพาณิชย์'),
                Tab(text: 'PromptPay'),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 170,
            child: TabBarView(
              controller: _tab,
              children: [
                _infoCard(kBankInfo),
                _infoCard(kPromptPayInfo),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('หลักฐานการชำระเงิน (≤1MB)',
                style: Theme.of(context).textTheme.bodySmall),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              FilledButton.icon(
                onPressed: _submitting ? null : _pick,
                icon: const Icon(Icons.attach_file),
                label: Text(_file == null ? 'Choose File' : 'เปลี่ยนไฟล์'),
              ),
              const SizedBox(width: 10),
              if (_file != null)
                Expanded(
                  child:
                      Text(_file!.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              if (_file != null)
                IconButton(
                  onPressed:
                      _submitting ? null : () => setState(() => _file = null),
                  icon: const Icon(Icons.delete_outline),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed:
                      _submitting ? null : () => Navigator.pop(context, null),
                  child: const Text('ยกเลิก'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _submitting || _file == null
                      ? null
                      : () => Navigator.pop(
                          context, _PaymentProofResult(_channel, _file!)),
                  child: _submitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('ยืนยันการชำระเงิน'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


// 🚀 [แก้ไข] WIDGET สำหรับ BOTTOMSHEET เลือกคูปอง
// ===== BottomSheet เลือกคูปอง (เวอร์ชันกันกดคูปองที่ถูก hold) =====
class _CouponSelectionSheet extends StatelessWidget {
  const _CouponSelectionSheet({required this.subtotal});
  final double subtotal;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fmt = DateFormat('dd/MM/yy');
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('เลือกคูปองส่วนลด',
                      style: Theme.of(context).textTheme.titleLarge),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context, null),
                  ),
                ],
              ),
            ),
            Expanded(
              child: (uid == null)
                  ? const Center(child: Text('กรุณาเข้าสู่ระบบเพื่อใช้คูปอง'))
                  : StreamBuilder<List<Coupon>>(
                      stream: FirestoreService.instance
                          .streamMyClaimedCoupons(uid),
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const Center(
                              child: CircularProgressIndicator());
                        }
                        final coupons = snap.data ?? <Coupon>[];
                        if (coupons.isEmpty) {
                          return const Center(
                              child: Text('คุณยังไม่มีคูปองที่เก็บไว้'));
                        }

                        return ListView(
                          controller: scrollController,
                          children: [
                            ListTile(
                              leading: Icon(Icons.clear,
                                  color: cs.onSurfaceVariant),
                              title: const Text('ไม่ใช้ส่วนลด'),
                              onTap: () => Navigator.pop(context, null),
                            ),
                            const Padding(
                              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                              child: Text('คูปองที่มี'),
                            ),

                            // ตรวจทีละใบด้วย validateCoupon: ถ้า error = ใช้ไม่ได้ -> disable + แสดงเหตุผล
                            ...coupons.map((c) {
                              return FutureBuilder<Coupon>(
                                future: FirestoreService.instance
                                    .validateCoupon(uid, c.code, subtotal),
                                builder: (context, v) {
                                  final usable =
                                      v.connectionState == ConnectionState.done &&
                                      v.hasData;
                                  String? reason;
                                  if (v.connectionState ==
                                          ConnectionState.done &&
                                      v.hasError) {
                                    // ดึงข้อความ error จาก validateCoupon เพื่อแสดงเป็นเหตุผล
                                    reason = v.error.toString();
                                  }

                                  final isLoading =
                                      v.connectionState == ConnectionState.waiting;

                                  // UI
                                  final title = Text(
                                    c.code,
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: usable
                                          ? cs.primary
                                          : cs.onSurfaceVariant,
                                    ),
                                  );

                                  final subTexts = <Widget>[
                                    if (c.description.trim().isNotEmpty)
                                      Text(
                                        c.description,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall,
                                      ),
                                    if (reason != null)
                                      Text(
                                        reason,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: cs.onSurfaceVariant,
                                            ),
                                      ),
                                  ];

                                  return ListTile(
                                    enabled: usable && !isLoading,
                                    leading: Icon(
                                      Icons.local_offer,
                                      color: usable
                                          ? cs.primary
                                          : cs.onSurfaceVariant,
                                    ),
                                    title: title,
                                    subtitle: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        ...subTexts,
                                        Text(
                                          'หมดอายุ ${fmt.format(c.expiryDate.toDate())}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall,
                                        ),
                                      ],
                                    ),
                                    trailing: isLoading
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          )
                                        : (usable
                                            ? const Icon(
                                                Icons.chevron_right)
                                            : Icon(Icons.block,
                                                color:
                                                    cs.onSurfaceVariant)),
                                    onTap: (usable && !isLoading)
                                        ? () => Navigator.pop(context, c)
                                        : null,
                                  );
                                },
                              );
                            }).toList(),
                          ],
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}