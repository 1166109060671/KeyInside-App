// lib/features/admin/admin_orders_tab.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/firestore_service.dart';
import 'order_detail_page.dart'; // ใช้ไปหน้า detail แบบส่ง docId ตรง

class AdminOrdersTab extends StatefulWidget {
  const AdminOrdersTab({super.key});

  @override
  State<AdminOrdersTab> createState() => _AdminOrdersTabState();
}

class _AdminOrdersTabState extends State<AdminOrdersTab> {
  final _money = NumberFormat('#,##0.00');
  String _status = 'all';           // all | pending | paid | cancelled
  String _q = '';                   // ค้นหา (#orderId หรือ email)

  static const _statuses = ['all', 'pending', 'paid', 'cancelled'];
  static const _labels   = {
    'all': 'All',
    'pending': 'Pending',
    'paid': 'Paid',
    'cancelled': 'Cancelled',
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final stream = FirestoreService.instance.streamOrders(
      status: _status,
      searchText: _q.isEmpty ? null : _q,
      limit: 300,
    );

    return Column(
      children: [
        // ── ตัวกรองสถานะ ──
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Row(
            children: _statuses.map((s) {
              final selected = s == _status;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(_labels[s] ?? s),
                  selected: selected,
                  onSelected: (_) => setState(() => _status = s),
                  selectedColor: cs.primaryContainer,
                  labelStyle: TextStyle(
                    color: selected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        // ── ช่องค้นหา ──
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'ค้นหา #Order หรือ Email',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _q = v.trim()),
          ),
        ),

        // ── รายการออเดอร์ ──
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
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                itemCount: orders.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final o = orders[i];
                  final orderId = (o['orderId'] ?? o['docId']).toString();
                  final status = (o['status'] ?? 'pending').toString().toLowerCase();
                  final name   = (o['buyerName'] ?? '-').toString();
                  final email  = (o['email'] ?? '-').toString();
                  final method = (o['paymentMethod'] ?? '-').toString();
                  final total  = ((o['total'] ?? 0) as num).toDouble();

                  final (bg, fg) = _statusColors(context, status);

                  return InkWell(
                    onTap: () {
                      // ไปหน้าแอดมินดูรายละเอียดออเดอร์ (ไฟล์มีอยู่แล้ว)
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => OrderDetailPage(docId: o['docId']),
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest.withOpacity(.5),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
                            child: Text(
                              status.toUpperCase(),
                              style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 11),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Order', style: Theme.of(context).textTheme.labelSmall),
                                Text('#$orderId',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.w700)),
                                const SizedBox(height: 6),
                                Text(name, style: Theme.of(context).textTheme.bodyMedium),
                                Text(email, style: Theme.of(context).textTheme.bodySmall),
                                const SizedBox(height: 6),
                                Text(
                                  'สถานะ: ${status.toUpperCase()} • $method • ฿ ${_money.format(total)}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right),
                        ],
                      ),
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

  (Color, Color) _statusColors(BuildContext context, String status) {
    final cs = Theme.of(context).colorScheme;
    switch (status) {
      case 'paid': return (cs.secondaryContainer, cs.onSecondaryContainer);
      case 'cancelled': return (Colors.red.withOpacity(.15), Colors.red);
      case 'pending':
      default: return (cs.surfaceContainerHighest, cs.onSurfaceVariant);
    }
  }
}
