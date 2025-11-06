// lib/features/orders/my_orders_page.dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart'; // Clipboard

class MyOrdersPage extends StatefulWidget {
  const MyOrdersPage({super.key});

  @override
  State<MyOrdersPage> createState() => _MyOrdersPageState();
}

class _MyOrdersPageState extends State<MyOrdersPage> {
  String _filter = 'pending'; // pending | paid | cancelled
  final _money = NumberFormat('#,##0.00');

  Stream<QuerySnapshot<Map<String, dynamic>>>? _buildStream() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;

    final col = FirebaseFirestore.instance.collection('orders');

    // ✅ orderBy ควรมาก่อน limit
    return col
        .where('uid', isEqualTo: user.uid)
        .where('status', isEqualTo: _filter)
        .orderBy('createdAt', descending: true)
        .limit(200)
        .snapshots();
  }

  bool _canUserCancel(String status) => status == 'pending';

  Future<String?> _askCancelReason(BuildContext context) async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('สาเหตุการยกเลิก'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'เหตุผล (เช่น เปลี่ยนใจ / ใส่ที่อยู่ผิด)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('ยืนยัน')),
        ],
      ),
    );
    if (ok != true) return null;
    return ctl.text.trim().isEmpty ? 'ไม่มีเหตุผลระบุ' : ctl.text.trim();
  }

  Future<void> _cancelOrder(String docId) async {
    final reason = await _askCancelReason(context);
    if (reason == null) return;

    try {
      await FirebaseFirestore.instance.collection('orders').doc(docId).update({
        'status': 'cancelled',
        'cancelledBy': 'user',
        'cancelReason': reason,
        'cancelledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ยกเลิกออเดอร์เรียบร้อย')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ยกเลิกไม่สำเร็จ: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('My Orders')),
      body: Column(
        children: [
          _StatusFilter(
            value: _filter,
            onChanged: (v) => setState(() => _filter = v),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _buildStream(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('เกิดข้อผิดพลาด: ${snap.error}'));
                }
                final docs = snap.data?.docs ?? const [];
                if (docs.isEmpty) {
                  return _EmptyState(
                    title: 'ยังไม่มีคำสั่งซื้อ',
                    subtitle: 'ยังไม่มีคำสั่งซื้อในสถานะ “${_labelFromStatus(_filter)}”',
                  );
                }

                return RefreshIndicator(
                  onRefresh: () async => await Future.delayed(const Duration(milliseconds: 300)),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
                    itemBuilder: (_, i) {
                      final d = docs[i];
                      final data = d.data();
                      final orderId = (data['orderId'] ?? d.id).toString();
                      final status = (data['status'] ?? 'pending').toString();
                      final method = (data['paymentMethod'] ?? '-').toString();
                      final numTotal = (data['total'] ?? data['amount'] ?? 0) as num;
                      final total = numTotal.toDouble();
                      final ts = data['createdAt'];
                      final createdAt = ts is Timestamp
                          ? DateFormat('dd/MM/yyyy HH:mm').format(ts.toDate())
                          : '-';
                      final List items = (data['items'] as List? ?? const []);
                      final firstTitle = items.isNotEmpty
                          ? (items.first['title'] ?? '').toString()
                          : '(ไม่มีสินค้า)';

                      return _OrderTile(
                        orderId: orderId,
                        createdAt: createdAt,
                        title: firstTitle,
                        method: method,
                        totalText: '฿ ${_money.format(total)}',
                        status: status,
                        onTap: () => _showQuickDetail(context, d.id, data),
                        onCancel: null,
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemCount: docs.length,
                  ),
                );
              },
            ),
          ),
        ],
      ),
      backgroundColor: cs.surface,
    );
  }

  // ==================== Bottom Sheet (แสดงสินค้าพร้อมรูป, สลิป, KEY, และสรุปราคาพร้อมส่วนลด) ====================
  void _showQuickDetail(BuildContext context, String docId, Map<String, dynamic> data) {
    final orderId = (data['orderId'] ?? docId).toString();
    final status = (data['status'] ?? 'pending').toString();
    final method = (data['paymentMethod'] ?? '-').toString();
    final ts = data['createdAt'];
    final createdAt = ts is Timestamp
        ? DateFormat('dd/MM/yyyy HH:mm').format(ts.toDate())
        : '-';

    final List items = (data['items'] as List? ?? const []);
    // ===== คำนวณราคาแบบรองรับคูปอง =====
    double _subtotalFromItems(List items) {
      double sum = 0;
      for (final it in items) {
        final price = ((it['price'] ?? 0) as num).toDouble();
        final qty = ((it['qty'] ?? 0) as num).toInt();
        sum += price * qty;
      }
      return sum;
    }

    final savedSubtotal = (data['subtotal'] as num?)?.toDouble();
    final savedDiscount = (data['discount'] as num? ??
            data['discountAmount'] as num? ??
            0)
        .toDouble();
    final subtotal = savedSubtotal ?? _subtotalFromItems(items);
    final discount = savedDiscount.clamp(0, subtotal);
    final savedTotal = (data['total'] as num?)?.toDouble();
    final total = (savedTotal ?? (subtotal - discount)).clamp(0, subtotal);
    final couponCode =
        ((data['couponCode'] ?? data['appliedCouponCode'] ?? '') as String)
            .trim();

    final (bg, fg) = _statusColors(context, status);
    final canCancel = _canUserCancel(status);

    // สลิปชำระเงิน (รองรับ URL/BASE64)
    final String? proofUrl = (data['paymentProofUrl'] ?? data['paymentProof']) as String?;
    final String? proofB64 = (data['paymentProofBase64'] ?? '') as String?;
    Uint8List? proofBytes;
    if (proofB64 != null && proofB64.isNotEmpty) {
      proofBytes = _bytesFromDataUrl(proofB64);
    }

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        final cs = Theme.of(context).colorScheme;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: .65,
          maxChildSize: .95,
          minChildSize: .45,
          builder: (ctx, scrollCtl) => SingleChildScrollView(
            controller: scrollCtl,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text('Order #$orderId',
                                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        )),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(children: [
                            Icon(Icons.access_time, size: 14, color: cs.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Text(createdAt, style: Theme.of(ctx).textTheme.bodySmall),
                          ]),
                          const SizedBox(height: 2),
                          Row(children: [
                            Icon(Icons.account_balance_wallet_outlined,
                                size: 14, color: cs.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Text(method, style: Theme.of(ctx).textTheme.bodySmall),
                          ]),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
                      child: Text(
                        _labelFromStatus(status).toUpperCase(),
                        style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 11),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),
                Divider(color: cs.surfaceContainerHighest, height: 20),

                // Items (พร้อมรูป)
                ...items.map((raw) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: _GameLineItemSmart(
                      title: (raw['title'] ?? '').toString(),
                      platform: (raw['platform'] ?? '').toString(),
                      qty: ((raw['qty'] ?? 0) as num).toInt(),
                      price: ((raw['price'] ?? 0) as num).toDouble(),
                      inlineImage: _pickBestImage(raw),
                      productIdOrTitle: (raw['productId'] ??
                              raw['productID'] ??
                              raw['pid'] ??
                              raw['id'] ??
                              raw['title'] ??
                              '')
                          .toString(),
                      money: _money,
                    ),
                  );
                }),

                // Payment proof (สมส่วน)
                if (proofBytes != null || (proofUrl != null && proofUrl.isNotEmpty)) ...[
                  const SizedBox(height: 8),
                  Divider(color: cs.surfaceContainerHighest, height: 24),
                  Text('สลิปชำระเงิน',
                      style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          )),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      constraints: const BoxConstraints(maxHeight: 360),
                      width: double.infinity,
                      color: cs.surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: proofBytes != null
                          ? Image.memory(proofBytes, fit: BoxFit.contain)
                          : Image.network(
                              proofUrl!,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Container(
                                height: 220,
                                alignment: Alignment.center,
                                child: const Icon(Icons.broken_image),
                              ),
                            ),
                    ),
                  ),
                ],

                // ===== User Keys (เฉพาะเมื่อ PAID) =====
                if (status == 'paid') ...[
                  const SizedBox(height: 8),
                  Divider(color: cs.surfaceContainerHighest, height: 24),
                  Text('คีย์เกมของคุณ',
                      style: Theme.of(ctx).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          )),
                  const SizedBox(height: 8),

                  ...items.map((raw) {
                    final title = (raw['title'] ?? '').toString();
                    final qty = ((raw['qty'] ?? 0) as num).toInt();
                    final List<String> keys =
                        (raw['keys'] as List?)?.whereType<String>().toList() ?? const [];

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          if (keys.isEmpty)
                            Text('รอแอดมินปล่อยคีย์…', style: Theme.of(ctx).textTheme.bodySmall)
                          else
                            Column(
                              children: List.generate(keys.length, (i) {
                                final k = keys[i];
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: cs.surfaceContainerHighest.withOpacity(.5),
                                    borderRadius: BorderRadius.circular(12),
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
                                      IconButton(
                                        tooltip: 'คัดลอกคีย์',
                                        icon: const Icon(Icons.copy_all_outlined),
                                        onPressed: () {
                                          Clipboard.setData(ClipboardData(text: k));
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('คัดลอกคีย์แล้ว')),
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              }),
                            ),
                          if (qty > keys.length)
                            Text('ปล่อยแล้ว ${keys.length}/$qty คีย์',
                                style: Theme.of(ctx).textTheme.bodySmall),
                        ],
                      ),
                    );
                  }),
                ],

                Divider(color: cs.surfaceContainerHighest, height: 24),

                // ===== Summary (แสดงส่วนลดและโค้ด) =====
                _summaryRow('ยอดก่อนลด', '฿ ${_money.format(subtotal)}'),
                _summaryRow(
                  couponCode.isEmpty ? 'ส่วนลด' : 'ส่วนลด ($couponCode)',
                  '- ฿ ${_money.format(discount)}',
                ),
                const Divider(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('ยอดรวมสุทธิ', style: TextStyle(fontWeight: FontWeight.w700)),
                    Text('฿ ${_money.format(total)}',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  ],
                ),

                const SizedBox(height: 16),

                // Cancel & Close
                Row(
                  children: [
                    if (canCancel)
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await _cancelOrder(docId);
                          },
                          icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                          label: const Text('ยกเลิกออเดอร์',
                              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: Colors.red),
                            foregroundColor: Colors.red,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    if (canCancel) const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('ปิด'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------- base64 helper ----------
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

  // ---------- small UI helper ----------
  Widget _summaryRow(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(k), Text(v)],
        ),
      );
}

/* ---------------- image helpers ---------------- */

class ItemImage {
  final String? url;        // http(s) url
  final Uint8List? bytes;   // decoded base64 bytes
  const ItemImage({this.url, this.bytes});
}

ItemImage? _pickBestImage(Map<String, dynamic> item) {
  final img = _extractFromMap(item);
  if (img != null) return img;

  final prod = item['product'];
  if (prod is Map<String, dynamic>) {
    final nested = _extractFromMap(prod);
    if (nested != null) return nested;
  }

  final images = (item['images'] ?? item['pics']);
  if (images is List && images.isNotEmpty) {
    final first = images.first;
    if (first is String) return _fromString(first);
  }

  return null;
}

ItemImage? _extractFromMap(Map<String, dynamic> m) {
  final candidates = [
    m['imageUrl'],
    m['image'],
    m['cover'],
    m['thumbnail'],
    m['thumb'],
    m['url'],
  ];
  for (final c in candidates) {
    if (c is String && c.trim().isNotEmpty) {
      return _fromString(c.trim());
    }
  }
  return null;
}

ItemImage? _fromString(String s) {
  if (s.startsWith('data:image')) {
    final b = _bytesFromInlineDataUrl(s);
    if (b != null) return ItemImage(bytes: b);
    return null;
  }
  return ItemImage(url: s);
}

Uint8List? _bytesFromInlineDataUrl(String? dataUrl) {
  if (dataUrl == null || dataUrl.isEmpty) return null;
  final idx = dataUrl.indexOf('base64,');
  final raw = idx >= 0 ? dataUrl.substring(idx + 7) : dataUrl;
  try {
    return base64Decode(raw);
  } catch (_) {
    return null;
  }
}

Future<String?> _fetchProductImageUrl(String idOrTitle) async {
  if (idOrTitle.trim().isEmpty) return null;

  final products = FirebaseFirestore.instance.collection('products');

  // 1) ใช้ doc id ตรง ๆ
  final byId = await products.doc(idOrTitle).get();
  if (byId.exists) {
    final m = byId.data()!;
    final imgs = (m['images'] as List?)?.whereType<String>().toList() ?? const [];
    if (imgs.isNotEmpty) return imgs.first;
    for (final k in ['imageUrl', 'cover', 'thumbnail', 'thumb']) {
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) return v;
    }
  }

  // 2) lowerTitle
  final q1 = await products
      .where('lowerTitle', isEqualTo: idOrTitle.toLowerCase())
      .limit(1)
      .get();
  if (q1.docs.isNotEmpty) {
    final m = q1.docs.first.data();
    final imgs = (m['images'] as List?)?.whereType<String>().toList() ?? const [];
    if (imgs.isNotEmpty) return imgs.first;
    for (final k in ['imageUrl', 'cover', 'thumbnail', 'thumb']) {
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) return v;
    }
  }

  // 3) title ตรง ๆ
  final q2 = await products.where('title', isEqualTo: idOrTitle).limit(1).get();
  if (q2.docs.isNotEmpty) {
    final m = q2.docs.first.data();
    final imgs = (m['images'] as List?)?.whereType<String>().toList() ?? const [];
    if (imgs.isNotEmpty) return imgs.first;
    for (final k in ['imageUrl', 'cover', 'thumbnail', 'thumb']) {
      final v = m[k];
      if (v is String && v.trim().isNotEmpty) return v;
    }
  }

  return null;
}

/* ---------------- widgets ---------------- */

class _GameLineItemSmart extends StatelessWidget {
  const _GameLineItemSmart({
    required this.title,
    required this.platform,
    required this.qty,
    required this.price,
    required this.inlineImage,
    required this.productIdOrTitle,
    required this.money,
  });

  final String title;
  final String platform;
  final int qty;
  final double price;
  final ItemImage? inlineImage;
  final String productIdOrTitle;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (inlineImage != null) {
      return _GameLineItemBase(
        title: title,
        platform: platform,
        qty: qty,
        price: price,
        thumb: _thumbFromItemImage(inlineImage!, cs),
        money: money,
      );
    }

    return FutureBuilder<String?>(
      future: _fetchProductImageUrl(productIdOrTitle.isNotEmpty ? productIdOrTitle : title),
      builder: (context, snap) {
        Widget thumb;
        if (snap.connectionState == ConnectionState.waiting) {
          thumb = Container(
            color: cs.surfaceContainerHighest,
            alignment: Alignment.center,
            child: const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          );
        } else if (snap.data != null && (snap.data!).isNotEmpty) {
          thumb = Image.network(
            snap.data!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                Container(color: cs.surfaceContainerHighest, child: const Icon(Icons.broken_image)),
          );
        } else {
          thumb = Container(color: cs.surfaceContainerHighest, child: const Icon(Icons.videogame_asset));
        }

        return _GameLineItemBase(
          title: title,
          platform: platform,
          qty: qty,
          price: price,
          thumb: thumb,
          money: money,
        );
      },
    );
  }

  Widget _thumbFromItemImage(ItemImage img, ColorScheme cs) {
    if (img.bytes != null) {
      return Image.memory(img.bytes!, fit: BoxFit.cover);
    }
    if (img.url != null) {
      return Image.network(
        img.url!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            Container(color: cs.surfaceContainerHighest, child: const Icon(Icons.broken_image)),
      );
    }
    return Container(color: cs.surfaceContainerHighest, child: const Icon(Icons.videogame_asset));
  }
}

class _GameLineItemBase extends StatelessWidget {
  const _GameLineItemBase({
    required this.title,
    required this.platform,
    required this.qty,
    required this.price,
    required this.thumb,
    required this.money,
  });

  final String title;
  final String platform;
  final int qty;
  final double price;
  final Widget thumb;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(width: 56, height: 56, child: thumb),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              if (platform.isNotEmpty)
                Text(platform, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text('x$qty • ฿ ${money.format(price)}'),
      ],
    );
  }
}

class _StatusFilter extends StatelessWidget {
  const _StatusFilter({required this.value, required this.onChanged});
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = const ['pending', 'paid', 'cancelled'];
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: items.map((s) {
          final selected = value == s;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(_labelFromStatus(s)),
              selected: selected,
              onSelected: (_) => onChanged(s),
              selectedColor: cs.primaryContainer,
              labelStyle: TextStyle(
                color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile({
    required this.orderId,
    required this.createdAt,
    required this.title,
    required this.method,
    required this.totalText,
    required this.status,
    required this.onTap,
    this.onCancel,
  });

  final String orderId;
  final String createdAt;
  final String title;
  final String method;
  final String totalText;
  final String status;
  final VoidCallback onTap;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final (bg, fg) = _statusColors(context, status);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withOpacity(.5),
          borderRadius: BorderRadius.circular(14),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: cs.primaryContainer,
              child: Icon(Icons.receipt_long, color: cs.onPrimaryContainer),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Order #$orderId',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text('$method • $createdAt',
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _labelFromStatus(status).toUpperCase(),
                    style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 11),
                  ),
                ),
                const SizedBox(height: 8),
                Text(totalText, style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.history, size: 46, color: cs.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: cs.onSurface)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: cs.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}

/* ---------------- helpers ---------------- */

String _labelFromStatus(String s) {
  switch (s) {
    case 'pending':
      return 'Pending';
    case 'paid':
      return 'Paid';
    case 'cancelled':
      return 'Cancelled';
    default:
      return 'Unknown';
  }
}

(Color, Color) _statusColors(BuildContext context, String status) {
  final cs = Theme.of(context).colorScheme;
  switch (status) {
    case 'paid':
      return (cs.secondaryContainer, cs.onSecondaryContainer);
    case 'cancelled':
      return (Colors.red.withOpacity(.15), Colors.red);
    case 'pending':
    default:
      return (cs.surfaceContainerHighest, cs.onSurfaceVariant);
  }
}
