// lib/models/game_product.dart
import 'package:cloud_firestore/cloud_firestore.dart';

/// ตัวเลือกของสินค้า (เช่น Standard, Deluxe) ที่เก็บแบบ map ภายใต้ฟิลด์ `variants`
class VariantOption {
  final String key;         // 'standard', 'deluxe'
  final String name;        // ชื่อที่แสดง
  final double? price;      // ราคา override (null = ใช้ราคา base)
  final int? stock;         // สต๊อก override (null = ใช้สต๊อก base)
  final String sku;         // ถ้ามีกำหนด

  const VariantOption({
    required this.key,
    required this.name,
    this.price,
    this.stock,
    this.sku = '',
  });

  VariantOption copyWith({
    String? key,
    String? name,
    double? price,
    int? stock,
    String? sku,
  }) {
    return VariantOption(
      key: key ?? this.key,
      name: name ?? this.name,
      price: price ?? this.price,
      stock: stock ?? this.stock,
      sku: sku ?? this.sku,
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        if (price != null) 'price': price,
        if (stock != null) 'stock': stock,
        if (sku.isNotEmpty) 'sku': sku,
      };

  factory VariantOption.fromEntry(String key, Map<String, dynamic> m) {
    return VariantOption(
      key: key,
      name: (m['name'] ?? key).toString(),
      price: GameProduct._toDoubleNullable(m['price']),
      stock: GameProduct._toIntNullable(m['stock']),
      sku: (m['sku'] ?? '').toString(),
    );
  }
}

class GameProduct {
  final String id;
  final String title;
  final String platform;
  final String region;
  final double price;        // base price (ใช้เมื่อ variant ไม่กำหนดราคา)
  final int stock;           // base stock (ใช้เมื่อ variant ไม่กำหนดสต๊อก)
  final List<String> images;

  /// key -> VariantOption (เช่น {'standard': {...}, 'deluxe': {...}})
  final Map<String, VariantOption> variants;

  const GameProduct({
    required this.id,
    required this.title,
    required this.platform,
    required this.region,
    required this.price,
    required this.stock,
    this.images = const [],
    this.variants = const {},
  });

  // ---- computed flags ----
  bool get hasVariants => variants.isNotEmpty;
  bool get isOutOfStock => stockFor(null) == 0;
  bool get isLowStock => !isOutOfStock && stockFor(null) < 10;

  // ---- Firestore encode ----
  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'lowerTitle': title.toLowerCase(),
        'platform': platform,
        'region': region,
        'price': price,
        'stock': stock,
        'images': images,
        if (variants.isNotEmpty)
          'variants': variants.map((k, v) => MapEntry(k, v.toMap())),
      };

  // ---- helpers for safe parsing ----
  static String _cleanStr(dynamic x) {
    final s = x?.toString() ?? '';
    return s
        .replaceAll('"', '')
        .replaceAll('“', '')
        .replaceAll('”', '')
        .replaceAll('’', '')
        .replaceAll('‘', '')
        .trim();
  }

  static double _toDouble(dynamic v) {
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(_cleanStr(v)) ?? 0;
    return 0;
  }

  static double? _toDoubleNullable(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(_cleanStr(v));
    return null;
  }

  static int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(_cleanStr(v)) ?? 0;
    return 0;
  }

  static int? _toIntNullable(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(_cleanStr(v));
    return null;
  }

  static List<String> _toStringList(dynamic raw) {
    if (raw is List) {
      return raw.map((e) => _cleanStr(e)).where((e) => e.isNotEmpty).toList();
    }
    if (raw is String) {
      final s = _cleanStr(raw);
      if (s.contains(',')) {
        return s.split(',').map(_cleanStr).where((e) => e.isNotEmpty).toList();
      }
      return s.isEmpty ? <String>[] : <String>[s];
    }
    return <String>[];
  }

  // ---- decode from Firestore map ----
  factory GameProduct.fromMap(Map<String, dynamic> data, String docId) {
    // parse variants map
    final Map<String, VariantOption> vmap = {};
    final rawV = data['variants'];
    if (rawV is Map) {
      rawV.forEach((k, v) {
        if (v is Map<String, dynamic>) {
          vmap[k.toString()] = VariantOption.fromEntry(k.toString(), v);
        } else if (v is Map) {
          vmap[k.toString()] =
              VariantOption.fromEntry(k.toString(), Map<String, dynamic>.from(v));
        }
      });
    }

    final _id = _cleanStr(data['id'] ?? docId);
    return GameProduct(
      id: _id.isEmpty ? docId : _id,
      title: _cleanStr(data['title']),
      platform: _cleanStr(data['platform']),
      region: _cleanStr(data['region']),
      price: _toDouble(data['price']),
      stock: _toInt(data['stock']),
      images: _toStringList(data['images']),
      variants: vmap,
    );
  }

  /// ใช้ generic `DocumentSnapshot<Map<String,dynamic>>` เพื่อลดการ cast
  factory GameProduct.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final map = doc.data() ?? <String, dynamic>{};
    return GameProduct.fromMap(map, doc.id);
  }

  GameProduct copyWith({
    String? id,
    String? title,
    String? platform,
    String? region,
    double? price,
    int? stock,
    List<String>? images,
    Map<String, VariantOption>? variants,
  }) {
    return GameProduct(
      id: id ?? this.id,
      title: title ?? this.title,
      platform: platform ?? this.platform,
      region: region ?? this.region,
      price: price ?? this.price,
      stock: stock ?? this.stock,
      images: images ?? this.images,
      variants: variants ?? this.variants,
    );
  }

  /// ดึงตัวเลือกจาก key (null/ว่าง = ไม่มี)
  VariantOption? getVariant(String? key) {
    if (key == null || key.trim().isEmpty) return null;
    return variants[key.trim()];
  }

  /// ราคาใช้งานจริง: ถ้า variant ตั้งราคาไว้ → ใช้ราคา variant, ไม่งั้นใช้ base
  double effectivePriceFor(String? variantKey) {
    final v = getVariant(variantKey);
    final vp = v?.price;
    return (vp != null && vp > 0) ? vp : price;
  }

  /// สต๊อกใช้งานจริง: ถ้า variant ตั้งสต๊อกไว้ → ใช้ของ variant, ไม่งั้นใช้ base
  int stockFor(String? variantKey) {
    final v = getVariant(variantKey);
    final vs = v?.stock;
    return (vs != null && vs >= 0) ? vs : stock;
  }
}
