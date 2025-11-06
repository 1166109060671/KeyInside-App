// lib/features/admin/admin_dashboard_page.dart
import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import 'package:keyinside/features/admin/chats/admin_chat_list_page.dart';
import 'package:keyinside/features/admin/order_detail_page.dart';

import '../../models/coupon.dart';
import '../../models/game_product.dart';
import '../../services/firestore_service.dart';

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this); // 4 แท็บ
    _tabCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isProductsTab = _tabCtrl.index == 0;
    final isCouponsTab = _tabCtrl.index == 3;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        bottom: TabBar(
          controller: _tabCtrl,
          tabAlignment: TabAlignment.fill,
          tabs: const [
            Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Products'),
            Tab(icon: Icon(Icons.receipt_long_outlined), text: 'Orders'),
            Tab(icon: Icon(Icons.chat_bubble_outline), text: 'Chats'),
            Tab(icon: Icon(Icons.local_offer_outlined), text: 'Coupons'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        physics: const NeverScrollableScrollPhysics(),
        children: const [
          _ProductsBody(),
          _OrdersBody(),
          AdminChatListPage(),
          _CouponsBody(),
        ],
      ),
      floatingActionButton: (isProductsTab || isCouponsTab)
          ? FloatingActionButton.extended(
              onPressed: () {
                if (isProductsTab) {
                  _openEditor(context);
                } else if (isCouponsTab) {
                  _openCouponEditor(context);
                }
              },
              icon: const Icon(Icons.add),
              label: Text(isProductsTab ? 'Add product' : 'Add coupon'),
            )
          : null,
    );
  }
}

/* -------------------- PRODUCTS: BODY ONLY -------------------- */
class _ProductsBody extends StatelessWidget {
  const _ProductsBody();

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('products')
        .orderBy('title')
        .snapshots();

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text('ยังไม่มีสินค้า'));
        }

        final items = docs
            .map((d) => GameProduct.fromMap(
                  (d.data() as Map<String, dynamic>?) ?? {},
                  d.id,
                ))
            .toList();

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final p = items[i];

            Widget thumb;
            if (p.images.isNotEmpty && p.images.first.startsWith('http')) {
              thumb = Image.network(p.images.first, fit: BoxFit.cover);
            } else if (p.images.isNotEmpty &&
                p.images.first.startsWith('data:image')) {
              try {
                final bytes = base64Decode(p.images.first.split(',').last);
                thumb = Image.memory(bytes, fit: BoxFit.cover);
              } catch (_) {
                thumb = const Icon(Icons.broken_image);
              }
            } else {
              thumb = Container(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withOpacity(.6),
                child: const Icon(Icons.image_not_supported),
              );
            }

            return Card(
              child: ListTile(
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: AspectRatio(aspectRatio: 1, child: thumb),
                ),
                title: Text(
                  p.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${p.platform} • ${p.region} • ฿ ${p.price.toStringAsFixed(2)} • stock: ${p.stock}',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Edit',
                      onPressed: () => _openEditor(context, existing: p),
                      icon: const Icon(Icons.edit_outlined),
                    ),
                    IconButton(
                      tooltip: 'Delete',
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          useRootNavigator: true, // ✅ ป้องกัน pop ผิดตัว
                          builder: (dialogContext) => AlertDialog(
                            title: const Text('ลบสินค้า?'),
                            content: Text('ยืนยันลบ “${p.title}”'),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(false),
                                child: const Text('ยกเลิก'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    Navigator.of(dialogContext).pop(true),
                                child: const Text('ลบ'),
                              ),
                            ],
                          ),
                        );

                        if (ok == true) {
                          try {
                            await FirestoreService.instance.deleteProduct(p.id);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('ลบสินค้าแล้ว')),
                              );
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('เกิดข้อผิดพลาด: $e')),
                              );
                            }
                          }
                        }
                      },
                      icon:
                          const Icon(Icons.delete_outline, color: Colors.red),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/* -------------------- ORDERS: BODY -------------------- */
class _OrdersBody extends StatefulWidget {
  const _OrdersBody();
  @override
  State<_OrdersBody> createState() => _OrdersBodyState();
}

class _OrdersBodyState extends State<_OrdersBody> {
  final _money = NumberFormat('#,##0.00');
  String _status = 'all';
  String _q = '';

  static const _statuses = ['all', 'pending', 'paid', 'cancelled'];
  static const _labels = {
    'all': 'ทั้งหมด',
    'pending': 'รอตรวจสอบ',
    'paid': 'ชำระแล้ว',
    'cancelled': 'ยกเลิก',
  };

  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirestoreService.instance.streamOrders(
      status: _status,
      limit: 300,
      searchText: _q.trim().isEmpty ? null : _q.trim(),
    );

    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: _statuses.map((s) {
              final selected = _status == s;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(_labels[s] ?? s),
                  selected: selected,
                  onSelected: (_) => setState(() => _status = s),
                ),
              );
            }).toList(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'ค้นหา #Order หรือ Email',
              prefixIcon: Icon(Icons.search),
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              if (_debounce?.isActive ?? false) _debounce!.cancel();
              _debounce = Timer(const Duration(milliseconds: 500), () {
                setState(() => _q = v);
              });
            },
          ),
        ),
        Expanded(
          child: StreamBuilder<List<Map<String, dynamic>>>(
            stream: stream,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(child: Text('เกิดข้อผิดพลาด: ${snap.error}'));
              }
              final orders = snap.data ?? const [];
              if (orders.isEmpty) {
                return const Center(child: Text('ไม่พบออเดอร์ในหมวดนี้'));
              }
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemCount: orders.length,
                itemBuilder: (_, i) {
                  final o = orders[i];
                  final docId = o['docId'] as String;
                  final orderId = (o['orderId'] ?? docId).toString();
                  final buyer = (o['buyerName'] ?? '-').toString();
                  final email = (o['email'] ?? '-').toString();
                  final status =
                      ((o['status'] ?? 'pending') as String).toLowerCase();
                  final method = (o['paymentMethod'] ?? '-').toString();
                  final total = ((o['total'] ?? 0) as num).toDouble();
                  return Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      leading: _StatusChip(status: status),
                      title: Text('Order #$orderId',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        '$buyer • $email\nสถานะ: ${status.toUpperCase()} • $method • ฿ ${_money.format(total)}',
                        style: const TextStyle(height: 1.3),
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => OrderDetailPage(docId: docId),
                          ),
                        );
                      },
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/* 🚀 -------------------- COUPONS: BODY (ยืนยันลบกดได้แน่นอน) -------------------- */
class _CouponsBody extends StatelessWidget {
  const _CouponsBody();

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('coupons')
        .orderBy('expiryDate', descending: true)
        .snapshots();

    final pageCtx = context;

    return StreamBuilder<QuerySnapshot>(
      stream: stream,
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Error: ${snap.error}'));
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(child: Text('ยังไม่มีคูปอง'));
        }

        final items = docs.map((d) => Coupon.fromDoc(d)).toList();
        final fmtDate = DateFormat('dd/MM/yyyy');
        final cs = Theme.of(pageCtx).colorScheme;

        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (itemCtx, i) {
            final c = items[i];
            final expired = c.isExpired;

            final discountText = c.isPercentage
                ? 'ลด ${c.discountValue.toStringAsFixed(0)}%'
                : 'ลด ฿${c.discountValue.toStringAsFixed(2)}';

            return Card(
              elevation: 0,
              color: expired ? cs.surfaceContainer : cs.surfaceContainerHighest,
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor:
                      expired ? cs.outlineVariant : cs.primaryContainer,
                  child: Icon(
                    Icons.local_offer_outlined,
                    color: expired ? cs.onSurfaceVariant : cs.onPrimaryContainer,
                  ),
                ),
                title: Text(
                  c.code,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: expired ? cs.onSurfaceVariant : cs.primary,
                    decoration: expired ? TextDecoration.lineThrough : null,
                  ),
                ),
                subtitle: Text(
                  '$discountText (ขั้นต่ำ ฿${c.minSpend.toStringAsFixed(0)}) • ${c.description}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'หมดอายุ ${fmtDate.format(c.expiryDate.toDate())}',
                      style: Theme.of(itemCtx).textTheme.bodySmall?.copyWith(
                            color: expired ? cs.error : cs.onSurfaceVariant,
                          ),
                    ),
                    IconButton(
                      tooltip: 'Delete Coupon',
                      onPressed: () async {
                        await _confirmDeleteCoupon(
                          pageCtx: context,
                          coupon: c,
                        );
                      },
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}


/* -------------------- PRODUCT EDITOR -------------------- */
class _ProductEditor extends StatefulWidget {
  const _ProductEditor({this.existing});
  final GameProduct? existing;

  @override
  State<_ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends State<_ProductEditor> {
  final _formKey = GlobalKey<FormState>();
  final _idCtl = TextEditingController();
  final _titleCtl = TextEditingController();
  final _platformCtl = TextEditingController();
  final _regionCtl = TextEditingController();
  final _priceCtl = TextEditingController();
  final _stockCtl = TextEditingController();

  final _picker = ImagePicker();
  final List<String> _images = [];
  // ✅ เพิ่ม: ตัวแปรสำหรับเก็บ Variants
  final List<VariantOption> _variants = [];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _idCtl.text = e.id;
      _titleCtl.text = e.title;
      _platformCtl.text = e.platform;
      _regionCtl.text = e.region;
      _priceCtl.text = e.price.toStringAsFixed(2);
      _stockCtl.text = e.stock.toString();
      _images.addAll(e.images);
      
      // ✅ โหลด Variants เดิม
      _variants.addAll(e.variants.values);
    }
  }

  @override
  void dispose() {
    _idCtl.dispose();
    _titleCtl.dispose();
    _platformCtl.dispose();
    _regionCtl.dispose();
    _priceCtl.dispose();
    _stockCtl.dispose();
    super.dispose();
  }

  Future<void> _pickFromDevice() async {
    final picks =
        await _picker.pickMultiImage(imageQuality: 70, maxWidth: 1200);
    if (picks.isEmpty) return;
    for (final img in picks) {
      final bytes = await img.readAsBytes();
      final b64 = "data:image/jpeg;base64,${base64Encode(bytes)}";
      _images.add(b64);
    }
    if (mounted) setState(() {});
  }

  Future<void> _addUrlDialog() async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (dCtx) => AlertDialog(
        title: const Text('เพิ่มรูปจาก URL'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'https://... .jpg/.png',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(dCtx).pop(false),
              child: const Text('ยกเลิก')),
          FilledButton(
              onPressed: () => Navigator.of(dCtx).pop(true),
              child: const Text('เพิ่ม')),
        ],
      ),
    );
    if (ok == true && ctl.text.trim().isNotEmpty) {
      _images.add(ctl.text.trim());
      if (mounted) setState(() {});
    }
  }

  void _removeAt(int i) {
    _images.removeAt(i);
    setState(() {});
  }

  // ✅ เพิ่ม: เมธอดสำหรับเปิด Variant Editor Dialog
  Future<void> _openVariantEditor(BuildContext context,
      {VariantOption? existing, int? index}) async {
    final result = await showDialog<VariantOption>(
      context: context,
      useRootNavigator: true,
      builder: (_) => _VariantEditorDialog(existing: existing),
    );

    if (result != null) {
      setState(() {
        if (existing != null && index != null) {
          // แก้ไข
          _variants[index] = result;
        } else {
          // เพิ่มใหม่
          _variants.add(result);
        }
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final cs = Theme.of(context).colorScheme;

    Widget? headerPreview;
    if (_images.isNotEmpty) {
      final first = _images.first;
      if (first.startsWith('http')) {
        headerPreview = Image.network(
          first,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.broken_image, size: 48),
        );
      } else if (first.startsWith('data:image')) {
        try {
          headerPreview = Image.memory(
            base64Decode(first.split(',').last),
            fit: BoxFit.cover,
          );
        } catch (_) {
          headerPreview = const Icon(Icons.broken_image, size: 48);
        }
      }
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        top: 16,
      ),
      child: Form(
        key: _formKey,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(isEdit ? 'แก้ไขสินค้า' : 'เพิ่มสินค้า',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),

            if (headerPreview != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(aspectRatio: 16 / 9, child: headerPreview),
                ),
              ),

            TextFormField(
              controller: _idCtl,
              decoration: const InputDecoration(
                labelText: 'ID (ใช้เป็น doc id ด้วย)',
                border: OutlineInputBorder(),
              ),
              enabled: !isEdit,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'กรอก ID' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _titleCtl,
              decoration: const InputDecoration(
                labelText: 'Title',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'กรอกชื่อสินค้า' : null,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _platformCtl,
                    decoration: const InputDecoration(
                      labelText: 'Platform',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'กรอก Platform' : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _regionCtl,
                    decoration: const InputDecoration(
                      labelText: 'Region',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? 'กรอก Region' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _priceCtl,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Price (THB)',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final d = double.tryParse(v ?? '');
                      return (d == null) ? 'ตัวเลขราคาไม่ถูกต้อง' : null;
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _stockCtl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Stock',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final x = int.tryParse(v ?? '');
                      return (x == null) ? 'ตัวเลข stock ไม่ถูกต้อง' : null;
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            // ====== ส่วนจัดการรูป ======
            Row(
              children: [
                Text('รูปสินค้า', style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: _addUrlDialog,
                  icon: const Icon(Icons.link),
                  label: const Text('เพิ่มจาก URL'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _pickFromDevice,
                  icon: const Icon(Icons.add_photo_alternate),
                  label: const Text('เพิ่มจากเครื่อง'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_images.isEmpty)
              Container(
                height: 80,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('ยังไม่มีรูป'),
              )
            else
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: List.generate(_images.length, (i) {
                  final s = _images[i];
                  Widget img;
                  if (s.startsWith('http')) {
                    img = Image.network(
                      s,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image),
                    );
                  } else {
                    try {
                      img = Image.memory(
                        base64Decode(s.split(',').last),
                        fit: BoxFit.cover,
                      );
                    } catch (_) {
                      img = const Icon(Icons.broken_image);
                    }
                  }
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: SizedBox(width: 100, height: 100, child: img),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: InkWell(
                          onTap: () => _removeAt(i),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            padding: const EdgeInsets.all(4),
                            child: const Icon(Icons.close,
                                size: 16, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ),
              
            const SizedBox(height: 16),
            // ✅ เพิ่ม: ====== ส่วนจัดการ Variants ======
            Row(
              children: [
                Text('ตัวเลือกย่อย (Variants)',
                    style: Theme.of(context).textTheme.titleMedium),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => _openVariantEditor(context),
                  icon: const Icon(Icons.add),
                  label: const Text('เพิ่มตัวเลือก'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_variants.isEmpty)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('ยังไม่มีตัวเลือกย่อย'),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _variants.length,
                itemBuilder: (context, i) {
                  final v = _variants[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(v.name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        'Key: ${v.key} • ราคา: ${v.price?.toStringAsFixed(2) ?? 'ใช้ Base Price'} • สต็อก: ${v.stock?.toString() ?? 'ใช้ Base Stock'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () =>
                                _openVariantEditor(context, existing: v, index: i),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline,
                                color: Colors.red),
                            onPressed: () =>
                                setState(() => _variants.removeAt(i)),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            // ✅ สิ้นสุดส่วนจัดการ Variants

            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('ยกเลิก'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    child: const Text('บันทึก'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true) return;

    // ✅ แปลง List<VariantOption> กลับเป็น Map<String, VariantOption>
    final variantsMap = Map.fromIterable(
      _variants,
      key: (v) => (v as VariantOption).key,
      value: (v) => v as VariantOption,
    );

    final product = GameProduct(
      id: _idCtl.text.trim(),
      title: _titleCtl.text.trim(),
      platform: _platformCtl.text.trim(),
      region: _regionCtl.text.trim(),
      price: double.parse(_priceCtl.text.trim()),
      stock: int.parse(_stockCtl.text.trim()),
      images: _images, // บันทึกทั้ง URL และ Base64
      variants: variantsMap, // ✅ เพิ่ม Variants
    );

    try {
      await FirestoreService.instance.upsertProduct(product);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('บันทึกสินค้าแล้ว')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')));
    }
  }
}

/* 🚀 -------------------- COUPON EDITOR -------------------- */
Future<void> _openCouponEditor(BuildContext context, {Coupon? existing}) async {
  await showModalBottomSheet(
    context: context,
    useRootNavigator: false,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _CouponEditor(existing: existing),
  );
}

class _CouponEditor extends StatefulWidget {
  const _CouponEditor({this.existing});
  final Coupon? existing;

  @override
  State<_CouponEditor> createState() => _CouponEditorState();
}

class _CouponEditorState extends State<_CouponEditor> {
  final _formKey = GlobalKey<FormState>();
  final _codeCtl = TextEditingController();
  final _descCtl = TextEditingController();
  final _valueCtl = TextEditingController();
  final _minCtl = TextEditingController();

  // ⬇️ ใหม่: จำกัดการใช้
  final _perUserCtl = TextEditingController();   // ต่อผู้ใช้
  final _globalCtl  = TextEditingController();   // รวมทั้งหมด
  bool _welcomeOneTime = false;                  // ปุ่มลัด “Welcome (1/คน)”

  String _type = 'fixed'; // fixed | percentage
  DateTime _expiry = DateTime.now().add(const Duration(days: 30));

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _codeCtl.text = e.code;
      _descCtl.text = e.description;
      _valueCtl.text = e.discountValue.toStringAsFixed(0);
      _minCtl.text = e.minSpend.toStringAsFixed(0);
      _type = e.discountType;
      _expiry = e.expiryDate.toDate();

      _perUserCtl.text = e.usageLimitPerUser.toString();
      _globalCtl.text  = e.usageLimitGlobal.toString();
      _welcomeOneTime  = e.usageLimitPerUser == 1;
    } else {
      _perUserCtl.text = '0';
      _globalCtl.text  = '0';
      _welcomeOneTime  = false;
    }
  }

  @override
  void dispose() {
    _codeCtl.dispose();
    _descCtl.dispose();
    _valueCtl.dispose();
    _minCtl.dispose();

    _perUserCtl.dispose();
    _globalCtl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final dt = await showDatePicker(
      context: context,
      initialDate: _expiry,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (dt != null) {
      setState(() => _expiry = dt);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final fmt = DateFormat('dd MMMM yyyy');

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Form(
        key: _formKey,
        child: ListView(
          shrinkWrap: true,
          children: [
            Text(isEdit ? 'แก้ไขคูปอง' : 'เพิ่มคูปองใหม่',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),

            TextFormField(
              controller: _codeCtl,
              decoration:
                  const InputDecoration(labelText: 'โค้ดคูปอง (เช่น SUMMER24)'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'กรอกโค้ด' : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _descCtl,
              decoration: const InputDecoration(
                  labelText: 'คำอธิบาย (เช่น ลด 10% ทั้งร้าน)'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'กรอกคำอธิบาย' : null,
            ),
            const SizedBox(height: 10),

            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'fixed', label: Text('ลด (บาท)'), icon: Text('฿')),
                ButtonSegment(value: 'percentage', label: Text('ลด (%)'), icon: Text('%')),
              ],
              selected: {_type},
              onSelectionChanged: (v) => setState(() => _type = v.first),
            ),
            const SizedBox(height: 10),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _valueCtl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'มูลค่าส่วนลด (เช่น 100 หรือ 15)'),
                    validator: (v) =>
                        (double.tryParse(v ?? '') == null) ? 'ตัวเลขไม่ถูก' : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _minCtl,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'ยอดขั้นต่ำ (เช่น 500)'),
                    validator: (v) =>
                        (double.tryParse(v ?? '') == null) ? 'ตัวเลขไม่ถูก' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'วันหมดอายุ',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              ),
              child: TextButton.icon(
                onPressed: _pickDate,
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(fmt.format(_expiry)),
              ),
            ),

            // ⬇️ ใหม่: UI จำกัดการใช้
            const SizedBox(height: 12),
            SwitchListTile(
              title: const Text('Welcome coupon (ใช้ได้คนละ 1 ครั้ง)'),
              value: _welcomeOneTime,
              onChanged: (v) {
                setState(() {
                  _welcomeOneTime = v;
                  if (v) _perUserCtl.text = '1';
                });
              },
              subtitle: const Text('ติ๊กแล้วระบบจะตั้งค่า “จำกัดต่อผู้ใช้ = 1” ให้อัตโนมัติ'),
            ),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _perUserCtl,
                    enabled: !_welcomeOneTime,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'จำกัดต่อผู้ใช้ (0 = ไม่จำกัด)',
                    ),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      return (n == null || n < 0) ? 'ตัวเลขไม่ถูกต้อง' : null;
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _globalCtl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'จำกัดรวมทั้งหมด (0 = ไม่จำกัด)',
                    ),
                    validator: (v) {
                      final n = int.tryParse(v ?? '');
                      return (n == null || n < 0) ? 'ตัวเลขไม่ถูกต้อง' : null;
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('ยกเลิก'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    child: const Text('บันทึก'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true) return;

    final id = widget.existing?.id ??
        FirebaseFirestore.instance.collection('coupons').doc().id;
    final code = _codeCtl.text.trim().toUpperCase();

    final perUser = _welcomeOneTime
        ? 1
        : (int.tryParse(_perUserCtl.text.trim()) ?? 0);
    final globalLimit = int.tryParse(_globalCtl.text.trim()) ?? 0;

    final data = {
      'id': id,
      'code': code,
      'description': _descCtl.text.trim(),
      'discountType': _type,
      'discountValue': double.tryParse(_valueCtl.text.trim()) ?? 0,
      'minSpend': double.tryParse(_minCtl.text.trim()) ?? 0,
      'expiryDate': Timestamp.fromDate(_expiry),
      'createdAt': FieldValue.serverTimestamp(),

      // ⬇️ ฟิลด์ใหม่สำหรับจำกัดการใช้
      'usageLimitPerUser': perUser,
      'usageLimitGlobal': globalLimit,
      // ให้มีฟิลด์ตัวนับไว้เสมอ (ไม่ทับค่าปัจจุบันเพราะ service ใช้ merge)
      'currentUsageCount': FieldValue.increment(0),
    };

    try {
      await FirestoreService.instance.upsertCoupon(id, data);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('บันทึกคูปองแล้ว')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('บันทึกไม่สำเร็จ: $e')));
    }
  }
}

/* -------------------- HELPERS -------------------- */
Future<void> _openEditor(BuildContext context, {GameProduct? existing}) async {
  await showModalBottomSheet(
    context: context,
    useRootNavigator: false,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _ProductEditor(existing: existing),
  );
}

/* -------------------- STATUS CHIP -------------------- */
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status; // expect: pending | paid | cancelled

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Color bg, fg;
    switch (status) {
      case 'paid':
        bg = cs.secondaryContainer;
        fg = cs.onSecondaryContainer;
        break;
      case 'cancelled':
        bg = Colors.red.withOpacity(.15);
        fg = Colors.red;
        break;
      case 'pending':
      default:
        bg = cs.surfaceContainerHighest;
        fg = cs.onSurfaceVariant;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(
        status.toUpperCase(),
        style:
            TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// ยืนยันการลบคูปอง (ใช้ pageCtx ที่ระดับหน้า เพื่อหลีกเลี่ยง context เสื่อมสภาพ)
Future<void> _confirmDeleteCoupon({
  required BuildContext pageCtx,
  required Coupon coupon,
}) async {
  bool didDelete = false;

  await showDialog<void>(
    context: pageCtx,
    barrierDismissible: true,
    useRootNavigator: false,
    builder: (dCtx) => AlertDialog(
      title: const Text('ลบคูปอง?'),
      content: Text('ยืนยันลบคูปอง “${coupon.code}”'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dCtx).pop(),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: () async {
            try {
              await FirestoreService.instance.deleteCoupon(coupon.id);
              didDelete = true;
            } catch (e) {
              if (pageCtx.mounted) {
                ScaffoldMessenger.of(pageCtx).showSnackBar(
                  SnackBar(content: Text('ลบไม่สำเร็จ: $e')),
                );
              }
            } finally {
              if (Navigator.of(dCtx).canPop()) {
                Navigator.of(dCtx).pop();
              }
            }
          },
          child: const Text('ลบ'),
        ),
      ],
    ),
  );

  if (didDelete && pageCtx.mounted) {
    ScaffoldMessenger.of(pageCtx).showSnackBar(
      SnackBar(content: Text('ลบคูปอง ${coupon.code} แล้ว')),
    );
  }
} 

// ✅ เพิ่ม: Variant Editor Dialog
class _VariantEditorDialog extends StatefulWidget {
  const _VariantEditorDialog({this.existing});
  final VariantOption? existing;

  @override
  State<_VariantEditorDialog> createState() => _VariantEditorDialogState();
}

class _VariantEditorDialogState extends State<_VariantEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  final _keyCtl = TextEditingController();
  final _nameCtl = TextEditingController();
  final _priceCtl = TextEditingController();
  final _stockCtl = TextEditingController();
  final _skuCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _keyCtl.text = e.key;
      _nameCtl.text = e.name;
      _priceCtl.text = e.price?.toStringAsFixed(2) ?? '';
      _stockCtl.text = e.stock?.toString() ?? '';
      _skuCtl.text = e.sku;
    }
  }

  @override
  void dispose() {
    _keyCtl.dispose();
    _nameCtl.dispose();
    _priceCtl.dispose();
    _stockCtl.dispose();
    _skuCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      title: Text(isEdit ? 'แก้ไขตัวเลือกย่อย' : 'เพิ่มตัวเลือกย่อยใหม่'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _keyCtl,
                enabled: !isEdit,
                decoration: const InputDecoration(
                    labelText: 'Key (ID อ้างอิง เช่น "standard")',
                    border: OutlineInputBorder(),
                    helperText: 'ต้องไม่ซ้ำกัน'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'กรอก Key' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _nameCtl,
                decoration: const InputDecoration(
                    labelText: 'ชื่อที่แสดง (เช่น "Standard Edition")',
                    border: OutlineInputBorder()),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'กรอกชื่อ' : null,
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _priceCtl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Override Price (฿)',
                  border: OutlineInputBorder(),
                  helperText: 'เว้นว่าง = ใช้ Base Price ของสินค้าหลัก',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final d = double.tryParse(v.trim());
                  return (d == null || d < 0) ? 'ตัวเลขไม่ถูกต้อง' : null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _stockCtl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Override Stock (ชิ้น)',
                  border: OutlineInputBorder(),
                  helperText: 'เว้นว่าง = ใช้ Base Stock ของสินค้าหลัก',
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return null;
                  final n = int.tryParse(v.trim());
                  return (n == null || n < 0) ? 'ตัวเลขไม่ถูกต้อง' : null;
                },
              ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _skuCtl,
                decoration: const InputDecoration(
                  labelText: 'SKU (รหัสสินค้าภายใน)',
                  border: OutlineInputBorder(),
                  helperText: 'ไม่บังคับ',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก')),
        FilledButton(
          onPressed: _save,
          child: const Text('บันทึก'),
        ),
      ],
    );
  }

  void _save() {
    if (_formKey.currentState?.validate() != true) return;

    final price = _priceCtl.text.trim().isNotEmpty
        ? double.tryParse(_priceCtl.text.trim())
        : null;
    final stock = _stockCtl.text.trim().isNotEmpty
        ? int.tryParse(_stockCtl.text.trim())
        : null;

    final result = VariantOption(
      key: _keyCtl.text.trim(),
      name: _nameCtl.text.trim(),
      price: price,
      stock: stock,
      sku: _skuCtl.text.trim(),
    );
    Navigator.pop(context, result);
  }
}