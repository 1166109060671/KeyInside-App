// lib/features/orders/order_detail_page.dart
import 'dart:convert';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart'; // สำหรับ Clipboard
import '../../services/firestore_service.dart';

class OrderDetailPage extends StatelessWidget {
  const OrderDetailPage({super.key, required this.docId});

  /// docId ของเอกสารในคอลเลคชัน "orders"
  final String docId;

  @override
  Widget build(BuildContext context) {
    final fmtMoney = NumberFormat('#,##0.00');
    final stream = FirebaseFirestore.instance
        .collection('orders')
        .doc(docId)
        .snapshots();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (snap.hasError) {
          return Scaffold(
              appBar: AppBar(),
              body: Center(child: Text('เกิดข้อผิดพลาด: ${snap.error}')));
        }
        if (!snap.hasData || !snap.data!.exists) {
          return const Scaffold(body: Center(child: Text('ไม่พบคำสั่งซื้อ')));
        }

        final data = snap.data!.data()!;
        final orderId = (data['orderId'] ?? snap.data!.id).toString();
        final status =
            ((data['status'] ?? 'pending') as String).toLowerCase();
        final buyer = (data['buyerName'] ?? '-').toString();
        final email = (data['email'] ?? '-').toString();
        final method = (data['paymentMethod'] ?? '-').toString();
        final note = (data['note'] ?? '').toString();

        // ----- ยอดเงิน -----
        // มีเก็บไว้ในเอกสารตอนสร้างออเดอร์แล้ว (subtotal/discount/total)
        // แต่ถ้าไม่มี ให้คำนวณ fallback จาก items
        final List<Map<String, dynamic>> items =
            (data['items'] as List? ?? const [])
                .whereType<Map<String, dynamic>>()
                .toList();

        double computedSubtotal = 0;
        for (final it in items) {
          final price = ((it['price'] ?? 0) as num).toDouble();
          final qty = ((it['qty'] ?? 0) as num).toInt();
          computedSubtotal += price * qty;
        }

        final num subtotalNumRaw = (data['subtotal'] ?? computedSubtotal) as num;
        final num discountNumRaw = (data['discount'] ?? 0) as num;
        final num totalNumRaw =
            (data['total'] ?? (subtotalNumRaw - discountNumRaw)) as num;

        final double subtotal = subtotalNumRaw.toDouble();
        final double discount = discountNumRaw.toDouble().clamp(0, subtotal);
        final double total = totalNumRaw.toDouble().clamp(0, subtotal);

        final couponCode = (data['couponCode'] ?? '').toString().trim();

        // ----- วันที่ -----
        final createdAt = data['createdAt'];
        final createdAtText = createdAt is Timestamp
            ? DateFormat('dd/MM/yyyy HH:mm').format(createdAt.toDate())
            : '-';

        // หลักฐานชำระเงิน
        final List<String> proofUrls = _extractProofUrls(data);
        final List<String> proofB64s = _extractProofBase64s(data);

        return Scaffold(
          appBar: AppBar(
            title: Text('Order #$orderId'),
            actions: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: _StatusChip(status: status),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // -------- ลูกค้า --------
              _SectionCard(
                title: 'ลูกค้า',
                children: [
                  _KV('ชื่อ', buyer),
                  _KV('อีเมล', email),
                  _KV('ช่องทางชำระเงิน', method),
                  if (note.trim().isNotEmpty) _KV('หมายเหตุ', note),
                  _KV('วันที่สั่งซื้อ', createdAtText),
                ],
              ),

              const SizedBox(height: 12),

              // -------- หลักฐานการชำระเงิน --------
              _SectionCard(
                title: 'หลักฐานการชำระเงิน',
                children: [
                  if (proofUrls.isEmpty && proofB64s.isEmpty)
                    Text('ยังไม่มีหลักฐานที่แนบมา',
                        style: Theme.of(context).textTheme.bodyMedium),
                  if (proofUrls.isNotEmpty) ...[
                    Text(
                      'จากลิงก์ (Storage/ภายนอก)',
                      style: Theme.of(context)
                          .textTheme
                          .labelLarge
                          ?.copyWith(
                              color:
                                  Theme.of(context).colorScheme.primary),
                    ),
                    const SizedBox(height: 8),
                    _ProofGridUrls(
                      urls: proofUrls,
                      onTapImage: (index) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => _ImageViewerUrlPage(
                                images: proofUrls, initialIndex: index),
                          ),
                        );
                      },
                    ),
                    if (proofB64s.isNotEmpty) const Divider(height: 24),
                  ],
                  if (proofB64s.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _ProofGridBase64(
                      base64s: proofB64s,
                      onTapImage: (index) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => _ImageViewerBase64Page(
                              imagesBase64: proofB64s,
                              initialIndex: index,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),

              const SizedBox(height: 12),

              // -------- รายการสินค้า --------
              _SectionCard(
                title: 'สินค้า (${items.length})',
                children: [
                  for (final raw in items)
                    _OrderItemTile(
                      title: (raw['title'] ?? '').toString(),
                      platform: (raw['platform'] ?? '').toString(),
                      price: ((raw['price'] ?? 0) as num).toDouble(),
                      qty: ((raw['qty'] ?? 0) as num).toInt(),
                      fmt: fmtMoney,
                    ),
                ],
              ),

              // -------- Game Keys (เฉพาะตอน paid) --------
              if (status == 'paid') ...[
                const SizedBox(height: 12),
                _SectionCard(
                  title: 'Game Keys',
                  children: [
                    for (final raw in items) ...[
                      const SizedBox(height: 4),
                      Text((raw['title'] ?? '').toString(),
                          style:
                              const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      ...(((raw['keys'] as List?)
                                  ?.whereType<String>()
                                  .toList() ??
                              const []))
                          .map((k) => Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .surfaceVariant
                                      .withOpacity(.5),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        k,
                                        style: const TextStyle(
                                          fontFamily: 'monospace',
                                          letterSpacing: .5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                      if ((((raw['qty'] ?? 0) as num).toInt()) >
                          (((raw['keys'] as List?)?.length ?? 0)))
                        Text(
                          'ปล่อยแล้ว ${((raw['keys'] as List?)?.length ?? 0)}/${((raw['qty'] ?? 0) as num).toInt()} คีย์',
                          style:
                              Theme.of(context).textTheme.bodySmall,
                        ),
                      const SizedBox(height: 8),
                    ],
                  ],
                ),

                // ✅ ปุ่ม Generate Keys (quiet: true ไม่โชว์ error หน้าบ้านถ้า webhook ตอบ 405/302 ฯลฯ)
                const SizedBox(height: 12),
                SafeArea(
                  top: false,
                  child: FilledButton.icon(
                    onPressed: () async {
                      try {
                        // 1) เติมคีย์ให้ครบตาม qty
                        await FirestoreService.instance
                            .generateKeysForOrder(docId);

                        // 2) ตรวจค่า config
                        final url = FirestoreService.kWebhookUrl.trim();
                        final token =
                            FirestoreService.kSecretToken.trim();
                        if (url.isEmpty || token.isEmpty) {
                          throw 'ยังไม่ได้ตั้งค่า webhookUrl / token';
                        }

                        // 3) ส่งอีเมลผ่าน GAS แบบเงียบ
                        await FirestoreService.instance
                            .sendKeysEmailViaWebhook(
                          orderId: docId,
                          webhookUrl: url, // ต้องเป็น /exec
                          token: token, // ต้องตรงกับ SECRET_TOKEN ใน GAS
                          quiet: true, // เงียบ
                        );

                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text(
                                    'สร้างคีย์และส่งอีเมลให้ลูกค้าแล้ว ✅')),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content:
                                    Text('ดำเนินการแล้ว (มีคำเตือน): $e')),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.vpn_key_outlined),
                    label: const Text('Generate Keys'),
                  ),
                ),
              ],

              const SizedBox(height: 12),

              // -------- สรุป (โชว์ส่วนลด + โค้ด) --------
              _SectionCard(
                title: 'สรุป',
                children: [
                  _sumRow('ยอดก่อนลด', '฿ ${fmtMoney.format(subtotal)}'),
                  if (couponCode.isNotEmpty)
                    _sumRow('ส่วนลด ($couponCode)',
                        '- ฿ ${fmtMoney.format(discount)}')
                  else
                    _sumRow('ส่วนลด', '- ฿ ${fmtMoney.format(discount)}'),
                  const Divider(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('ยอดรวมสุทธิ',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      Text('฿ ${fmtMoney.format(total)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800)),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 20),
              _ActionButtons(
                  status: status,
                  orderDocId: docId,
                  parentContext: context),
            ],
          ),
        );
      },
    );
  }

  static List<String> _extractProofUrls(Map<String, dynamic> data) {
    final urls = <String>[];
    final single = data['paymentProofUrl'];
    if (single is String && single.trim().isNotEmpty) urls.add(single.trim());
    final list = data['paymentProofUrls'];
    if (list is List) {
      urls.addAll(
          list.whereType<String>().where((e) => e.trim().isNotEmpty));
    }
    return urls.toSet().toList();
  }

  static List<String> _extractProofBase64s(Map<String, dynamic> data) {
    final out = <String>[];
    final single = data['paymentProofBase64'];
    if (single is String && single.trim().isNotEmpty) out.add(single.trim());
    final list = data['paymentProofBase64s'];
    if (list is List) {
      out.addAll(
          list.whereType<String>().where((e) => e.trim().isNotEmpty));
    }
    return out
        .map((s) {
          final idx = s.indexOf('base64,');
          return idx >= 0 ? s.substring(idx + 7).trim() : s.trim();
        })
        .toList();
  }
}

/* ---------- Widgets / helpers ด้านล่างคงเดิม ---------- */

class _OrderItemTile extends StatelessWidget {
  const _OrderItemTile({
    required this.title,
    required this.platform,
    required this.price,
    required this.qty,
    required this.fmt,
  });

  final String title;
  final String platform;
  final double price;
  final int qty;
  final NumberFormat fmt;

  @override
  Widget build(BuildContext context) {
    final sub = price * qty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.videogame_asset_outlined, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(platform,
                    style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 6),
                Text('฿ ${fmt.format(price)} × $qty  =  ฿ ${fmt.format(sub)}'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              ...children,
            ]),
      ),
    );
  }
}

class _KV extends StatelessWidget {
  const _KV(this.k, this.v);
  final String k;
  final String v;

  @override
  Widget build(BuildContext context) {
    final styleK = Theme.of(context).textTheme.bodyMedium;
    final styleV = Theme.of(context)
        .textTheme
        .bodyMedium
        ?.copyWith(fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(k, style: styleK)),
          Text(v, style: styleV),
        ],
      ),
    );
  }
}

class _ProofGridUrls extends StatelessWidget {
  const _ProofGridUrls({required this.urls, required this.onTapImage});
  final List<String> urls;
  final void Function(int index) onTapImage;

  @override
  Widget build(BuildContext context) {
    if (urls.length == 1) {
      return _LargeProofImage.url(
          url: urls.first, onTap: () => onTapImage(0));
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: urls.length,
      gridDelegate:
          const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1),
      itemBuilder: (_, i) {
        final url = urls[i];
        return InkWell(
          onTap: () => onTapImage(i),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceVariant
                  .withOpacity(.35),
              alignment: Alignment.center,
              child: Image.network(url, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.broken_image)),
            ),
          ),
        );
      },
    );
  }
}

class _ProofGridBase64 extends StatelessWidget {
  const _ProofGridBase64(
      {required this.base64s, required this.onTapImage});
  final List<String> base64s;
  final void Function(int index) onTapImage;

  @override
  Widget build(BuildContext context) {
    if (base64s.length == 1) {
      return _LargeProofImage.base64(
          base64: base64s.first, onTap: () => onTapImage(0));
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: base64s.length,
      gridDelegate:
          const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1),
      itemBuilder: (_, i) {
        final bytes = base64Decode(base64s[i]);
        return InkWell(
          onTap: () => onTapImage(i),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceVariant
                  .withOpacity(.35),
              alignment: Alignment.center,
              child: Image.memory(bytes, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.broken_image)),
            ),
          ),
        );
      },
    );
  }
}

class _LargeProofImage extends StatelessWidget {
  const _LargeProofImage._({this.url, this.bytes, required this.onTap});
  _LargeProofImage.url({required String url, required VoidCallback onTap})
      : this._(url: url, bytes: null, onTap: onTap);
  _LargeProofImage.base64(
      {required String base64, required VoidCallback onTap})
      : this._(url: null, bytes: base64Decode(base64), onTap: onTap);

  final String? url;
  final Uint8List? bytes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 260,
        decoration: BoxDecoration(
            color: cs.surfaceVariant.withOpacity(.35),
            borderRadius: BorderRadius.circular(14)),
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: url != null
                ? Image.network(url!, fit: BoxFit.contain)
                : Image.memory(bytes!, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}

class _ImageViewerUrlPage extends StatefulWidget {
  const _ImageViewerUrlPage(
      {required this.images, this.initialIndex = 0});
  final List<String> images;
  final int initialIndex;
  @override
  State<_ImageViewerUrlPage> createState() => _ImageViewerUrlPageState();
}

class _ImageViewerUrlPageState extends State<_ImageViewerUrlPage> {
  late final PageController _pc =
      PageController(initialPage: widget.initialIndex);
  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black),
      body: PageView.builder(
        controller: _pc,
        itemCount: widget.images.length,
        itemBuilder: (_, i) => Center(
          child: InteractiveViewer(
            minScale: 0.5,
            maxScale: 4,
            child: Image.network(widget.images[i], fit: BoxFit.contain,
                errorBuilder: (_, __, ___) =>
                    const Icon(Icons.broken_image, color: Colors.white)),
          ),
        ),
      ),
    );
  }
}

class _ImageViewerBase64Page extends StatefulWidget {
  const _ImageViewerBase64Page(
      {required this.imagesBase64, this.initialIndex = 0});
  final List<String> imagesBase64;
  final int initialIndex;
  @override
  State<_ImageViewerBase64Page> createState() =>
      _ImageViewerBase64PageState();
}

class _ImageViewerBase64PageState extends State<_ImageViewerBase64Page> {
  late final PageController _pc =
      PageController(initialPage: widget.initialIndex);
  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black),
      body: PageView.builder(
        controller: _pc,
        itemCount: widget.imagesBase64.length,
        itemBuilder: (_, i) {
          final bytes = base64Decode(widget.imagesBase64[i]);
          return Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Image.memory(bytes, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) =>
                      const Icon(Icons.broken_image, color: Colors.white)),
            ),
          );
        },
      ),
    );
  }
}

/* ---------- Action buttons ---------- */
class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    required this.status, // pending | paid | cancelled
    required this.orderDocId, // docId จริงใน Firestore
    required this.parentContext, // ใช้เปิด dialog ผ่าน root navigator ให้เสถียร
  });

  final String status;
  final String orderDocId;
  final BuildContext parentContext;

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[];
    const gap = SizedBox(width: 12);
    void add(Widget w) => buttons.add(Expanded(child: w));

    if (status == 'pending') {
      add(OutlinedButton.icon(
        icon: const Icon(Icons.verified),
        label: const Text('Mark Paid'),
        onPressed: () async {
          final ok = await _confirm(
              title: 'ยืนยัน',
              message: 'อัปเดตสถานะเป็น “PAID” ใช่ไหม?',
              okText: 'ยืนยัน');
          if (!ok) return;
          await _withProgressAndRun(
            task: () =>
                FirestoreService.instance.markOrderPaid(orderDocId),
            successTitle: 'สำเร็จ',
            successMessage: 'อัปเดตเป็น PAID แล้ว',
          );
        },
      ));
      buttons.add(gap);
      add(FilledButton.icon(
        icon: const Icon(Icons.cancel_outlined),
        label: const Text('Cancel'),
        onPressed: () async {
          final reason = await _askCancelReason();
          if (reason == null) return;
          final ok = await _confirm(
            title: 'ยืนยัน',
            message: 'ยกเลิกออเดอร์นี้ใช่ไหม?\nเหตุผล: $reason',
            okText: 'ยืนยันยกเลิก',
          );
          if (!ok) return;
          await _withProgressAndRun(
            task: () => FirestoreService.instance
                .cancelOrder(orderDocId, reason: reason),
            successTitle: 'สำเร็จ',
            successMessage: 'ยกเลิกออเดอร์แล้ว',
          );
        },
      ));
    } else {
      add(OutlinedButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ย้อนกลับ')));
    }

    return Row(children: buttons);
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    String okText = 'ตกลง',
    String cancelText = 'ยกเลิก',
  }) async {
    final nav = Navigator.of(parentContext, rootNavigator: true);
    if (!nav.mounted) return false;
    final result = await showDialog<bool>(
      context: nav.context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => nav.pop(false), child: Text(cancelText)),
          FilledButton(
              onPressed: () => nav.pop(true), child: Text(okText)),
        ],
      ),
    );
    return result == true;
  }

  Future<String?> _askCancelReason() async {
    final nav = Navigator.of(parentContext, rootNavigator: true);
    if (!nav.mounted) return null;
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: nav.context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('สาเหตุการยกเลิก'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'เหตุผล (เช่น ชำระไม่สำเร็จ / ขอคืนเงิน)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => nav.pop(false),
              child: const Text('ยกเลิก')),
          FilledButton(
              onPressed: () => nav.pop(true),
              child: const Text('ยืนยัน')),
        ],
      ),
    );
    final reason = ctl.text.trim();
    return (ok == true && reason.isNotEmpty) ? reason : null;
  }

  Future<void> _withProgressAndRun({
    required Future<void> Function() task,
    String successTitle = 'สำเร็จ',
    required String successMessage,
  }) async {
    final nav = Navigator.of(parentContext, rootNavigator: true);
    if (!nav.mounted) return;
    final closeProgress = await _openProgress(nav);
    String? error;
    try {
      await task();
    } catch (e) {
      error = e.toString();
    }
    await closeProgress();
    if (!nav.mounted) return;
    await showDialog(
      context: nav.context,
      barrierDismissible: true,
      builder: (_) => AlertDialog(
        title: Text(error == null ? successTitle : 'เกิดข้อผิดพลาด'),
        content: Text(error ?? successMessage),
        actions: [
          FilledButton(
              onPressed: () => nav.pop(), child: const Text('ตกลง'))
        ],
      ),
    );
  }
}

Widget _sumRow(String label, String value) => Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(value),
      ],
    );

Future<Future<void> Function()> _openProgress(NavigatorState nav) async {
  bool closed = false;
  final future = showGeneralDialog(
    context: nav.context,
    barrierDismissible: false,
    barrierColor: Colors.black.withOpacity(0.25),
    pageBuilder: (_, __, ___) =>
        const Center(child: _ProgressHud()),
    transitionBuilder: (_, anim, __, child) =>
        FadeTransition(opacity: anim, child: child),
    transitionDuration: const Duration(milliseconds: 120),
  );
  return () async {
    if (closed) return;
    closed = true;
    if (nav.mounted && nav.canPop()) {
      nav.pop();
      await Future.delayed(const Duration(milliseconds: 30));
    }
    await future;
  };
}

class _ProgressHud extends StatelessWidget {
  const _ProgressHud();
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: Align(
        alignment: Alignment.center,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(.15), blurRadius: 20)
            ],
          ),
          margin: const EdgeInsets.symmetric(horizontal: 80),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 12),
              Text('กำลังดำเนินการ...'),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Color bg, fg;
    switch (status) {
      case 'pending':
        bg = cs.surfaceVariant;
        fg = cs.onSurfaceVariant;
        break;
      case 'paid':
        bg = cs.secondaryContainer;
        fg = cs.onSecondaryContainer;
        break;
      case 'cancelled':
        bg = Colors.red.withOpacity(.15);
        fg = Colors.red;
        break;
      default:
        bg = cs.surfaceVariant;
        fg = cs.onSurfaceVariant;
    }
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
            color: fg, fontWeight: FontWeight.w700, fontSize: 11),
      ),
    );
  }
}
