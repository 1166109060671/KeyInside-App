// lib/features/catalog/catalog_list_page.dart
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';                    // ✅ ใช้ดูจำนวนตะกร้า
import '../../app/app_routes.dart';
import '../../models/game_product.dart';
import '../../services/firestore_service.dart';
import '../../state/cart_provider.dart';                    // ✅ CartProvider ของโปรเจ็กต์

/*------------------------------------------------------
  Catalog List (Game Keys)
  ✅ โหลดจาก Firestore
  ✅ Filter/Search/Stock/Platform
  ✅ แถบล่างแบบ custom (ไม่ค้างเลือก) + เงื่อนไข admin/user
  ✅ Badge จำนวนในตะกร้า
-------------------------------------------------------*/

class CatalogListPage extends StatefulWidget {
  const CatalogListPage({super.key});

  @override
  State<CatalogListPage> createState() => _CatalogListPageState();
}

class _CatalogListPageState extends State<CatalogListPage> {
  final TextEditingController _searchCtl = TextEditingController();
  bool _isSearching = false;
  String platformFilter = 'ทั้งหมด';
  bool inStockOnly = false;
  String q = '';

  final List<String> platforms = const ['ทั้งหมด', 'Steam', 'Epic', 'Rockstar'];

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final stream = FirestoreService.instance.streamProducts(
      platform: platformFilter == 'ทั้งหมด' ? null : platformFilter,
      inStockOnly: inStockOnly,
      queryText: q,
    );

    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchCtl,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: (v) => setState(() => q = v),
                decoration: InputDecoration(
                  hintText: 'ค้นหาเกม...',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor:
                      Theme.of(context).colorScheme.surface.withOpacity(0.08),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
              )
            : const Text('Keys Inside'),
        actions: [
          IconButton(
            tooltip: _isSearching ? 'ปิดค้นหา' : 'ค้นหา',
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              if (_isSearching) _searchCtl.clear();
              _isSearching = !_isSearching;
            }),
          ),
        ],
      ),

      // ✅ แถบล่างแบบ custom: ไม่ค้าง highlight, มี ripple สวย ๆ + badge
      bottomNavigationBar: const _BottomActionsBar(),

      body: Column(
        children: [
          // ---- แถวตัวกรอง ----
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                PopupMenuButton<String>(
                  tooltip: 'เลือกแพลตฟอร์ม',
                  initialValue: platformFilter,
                  onSelected: (v) => setState(() => platformFilter = v),
                  itemBuilder: (context) => [
                    for (final plat in platforms)
                      PopupMenuItem(
                        value: plat,
                        child: Row(
                          children: [
                            Icon(_platformIcon(plat), size: 18),
                            const SizedBox(width: 8),
                            Text(plat),
                          ],
                        ),
                      ),
                  ],
                  child: OutlinedButton.icon(
                    onPressed: null,
                    icon: Icon(_platformIcon(platformFilter), size: 18),
                    label: Text(platformFilter),
                  ),
                ),
                const Spacer(),
                FilterChip(
                  label: const Text('มีสต๊อก'),
                  selected: inStockOnly,
                  onSelected: (v) => setState(() => inStockOnly = v),
                ),
              ],
            ),
          ),

          // ---- แสดงข้อมูลจาก Firestore ----
          Expanded(
            child: StreamBuilder<List<GameProduct>>(
              stream: stream,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('เกิดข้อผิดพลาด: ${snap.error}'));
                }
                final products = snap.data ?? [];
                if (products.isEmpty) {
                  return const Center(child: Text('ไม่พบสินค้า'));
                }

                return LayoutBuilder(
                  builder: (context, constraints) {
                    int columns = 2;
                    if (constraints.maxWidth >= 600) columns = 3;
                    if (constraints.maxWidth >= 900) columns = 4;

                    return GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: columns,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 0.85,
                      ),
                      itemCount: products.length,
                      itemBuilder: (context, i) => _ProductCard(p: products[i]),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------
// แถบล่างแบบ custom (ไม่ค้างเลือก) + badge ตะกร้า
// ---------------------------------------------------
// ---------------------------------------------------
// ✅ แถบล่างเรียบหรู Minimal (ไม่มีกรอบ ไม่มีปุ่มแยก)
// ---------------------------------------------------
class _BottomActionsBar extends StatelessWidget {
  const _BottomActionsBar();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final cartCount = context.select<CartProvider, int>((c) {
      // แก้ชื่อ getter ตาม CartProvider ของคุณ
      return c.items.length; // หรือ c.totalItems, c.cart.length
    });

    return SafeArea(
      top: false,
      child: Container(
        height: 68,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // ---- Chat / Admin ----
            StreamBuilder<User?>(
              stream: FirebaseAuth.instance.authStateChanges(),
              builder: (context, authSnap) {
                final user = authSnap.data;
                if (user == null) {
                  return _BottomIconButton(
                    icon: Icons.chat_bubble_outline,
                    label: 'แชท',
                    onTap: () => Navigator.pushNamed(context, AppRoutes.login),
                  );
                }
                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('users')
                      .doc(user.uid)
                      .snapshots(),
                  builder: (context, userSnap) {
                    final role = (userSnap.data?.data()?['role'] ?? '')
                        .toString()
                        .toLowerCase();
                    if (role == 'admin') {
                      return _BottomIconButton(
                        icon: Icons.admin_panel_settings_outlined,
                        label: 'Admin',
                        onTap: () => Navigator.pushNamed(
                            context, AppRoutes.adminDashboard),
                      );
                    } else {
                      return _BottomIconButton(
                        icon: Icons.chat_bubble_outline,
                        label: 'แชท',
                        onTap: () =>
                            Navigator.pushNamed(context, AppRoutes.userChat),
                      );
                    }
                  },
                );
              },
            ),

            // ---- ตะกร้า ----
            _BottomIconButton(
              icon: Icons.shopping_cart_outlined,
              label: 'ตะกร้า',
              badge: cartCount,
              onTap: () => Navigator.pushNamed(context, AppRoutes.cart),
            ),

            // ---- โปรไฟล์ ----
            _BottomIconButton(
              icon: Icons.person_outline,
              label: 'โปรไฟล์',
              onTap: () {
                final u = FirebaseAuth.instance.currentUser;
                if (u == null) {
                  Navigator.pushNamed(context, AppRoutes.login);
                } else {
                  Navigator.pushNamed(context, AppRoutes.profile);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------
// ปุ่มไอคอนเรียบ ๆ ใน BottomBar (ไม่มีกรอบ)
// ---------------------------------------------------
class _BottomIconButton extends StatelessWidget {
  const _BottomIconButton({
    required this.icon,
    required this.label,
    this.badge,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final int? badge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final hasBadge = (badge ?? 0) > 0;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      splashColor: Theme.of(context).colorScheme.primary.withOpacity(0.1),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 24),
                if (hasBadge)
                  Positioned(
                    right: -6,
                    top: -6,
                    child: _Badge(count: badge!),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------
// Badge (จุดแดงจำนวนในตะกร้า)
// ---------------------------------------------------
class _Badge extends StatelessWidget {
  const _Badge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final text = count > 99 ? '99+' : count.toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.error,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}




// ---------------------------------------------------

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.p});
  final GameProduct p;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: () => Navigator.pushNamed(
          context,
          AppRoutes.productDetail,
          arguments: p.id,
        ),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (p.images.isNotEmpty && p.images.first.startsWith('http'))
                        Image.network(
                          p.images.first,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Center(child: Icon(Icons.broken_image)),
                        )
                      else if (p.images.isNotEmpty && p.images.first.startsWith('data:image'))
                        Image.memory(
                          base64Decode(p.images.first.split(',').last),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              const Center(child: Icon(Icons.broken_image)),
                        )
                      else
                        Container(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withOpacity(.5),
                          child: const Center(
                            child: Icon(Icons.image_not_supported),
                          ),
                        ),
                      if (p.isOutOfStock)
                        Container(
                          color: Colors.black.withOpacity(0.55),
                          child: const Center(
                            child: Text(
                              'สินค้าหมด',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(_platformIcon(p.platform), size: 14),
                          const SizedBox(width: 4),
                          Text('${p.platform} • ${p.region}'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (p.isLowStock)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'เหลือ ${p.stock} key',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            Positioned(
              right: 8,
              bottom: 8,
              child: Text(
                '฿ ${p.price.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

IconData _platformIcon(String plat) {
  switch (plat) {
    case 'Steam':
      return Icons.sports_esports;
    case 'Epic':
      return Icons.storefront;
    case 'Rockstar':
      return Icons.star;
    default:
      return Icons.apps;
  }
}
