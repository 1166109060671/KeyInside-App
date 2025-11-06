// lib/state/cart_provider.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/game_product.dart';
import '../services/firestore_service.dart';

class CartItem {
  final String productId;
  final String title;
  final String platform;
  final double price;
  final int qty;
  final String? variantKey; // ✅ เพิ่ม: key สำหรับตัวเลือกย่อย

  const CartItem({
    required this.productId,
    required this.title,
    required this.platform,
    required this.price,
    required this.qty,
    this.variantKey, // ✅ เพิ่ม: key สำหรับตัวเลือกย่อย
  });

  // ใช้สำหรับสร้างรหัสที่ไม่ซ้ำกันใน local Map: {productId}::{variantKey}
  String get uniqueId => 
      '$productId${variantKey != null && variantKey!.isNotEmpty ? '::${variantKey!}' : ''}'; 
      
  // ใช้สำหรับส่งข้อมูลไปยัง Firestore
  String get firestoreDocId => productId; 

  CartItem copyWith({int? qty}) => CartItem(
        productId: productId,
        title: title,
        platform: platform,
        price: price,
        qty: qty ?? this.qty,
        variantKey: variantKey, // รักษาค่าเดิม
      );
}

class CartProvider extends ChangeNotifier {
  final _auth = FirebaseAuth.instance;

  // subscriptions
  StreamSubscription<User?>? _authSub;
  StreamSubscription? _cartSub;

  // local mirror ของ cart (ใช้แสดงผลทันที)
  // key: {productId}::{variantKey}
  final Map<String, CartItem> _items = {};
  List<CartItem> get items => _items.values.toList();
  double get total => _items.values.fold(0.0, (s, i) => s + (i.price * i.qty));
  bool get isEmpty => _items.isEmpty;
  int get itemCount => _items.length;

  CartProvider() {
    // ฟังสถานะผู้ใช้ แล้ว sync cart ตาม uid
    _authSub = _auth.userChanges().listen((user) {
      _cartSub?.cancel();
      _cartSub = null;

      _items.clear();
      notifyListeners();

      if (user != null) {
        // streamCart จะถูกแก้ไขใน FirestoreService ให้ส่ง variantKey กลับมาด้วย
        _cartSub = FirestoreService.instance.streamCart(user.uid).listen((rows) {
          _items.clear();
          for (final r in rows) {
            final productId = r['productId'] as String;
            final variantKey = r['variantKey'] as String?;
            
            final newItem = CartItem(
              productId: productId,
              title: r['title'] as String,
              platform: r['platform'] as String,
              price: (r['price'] as num).toDouble(),
              qty: (r['qty'] as num).toInt(),
              variantKey: variantKey, // ✅ ดึง variantKey
            );
            // ใช้ uniqueId เป็น key ใน Map
            _items[newItem.uniqueId] = newItem; 
          }
          notifyListeners();
        });
      }
    });
  }

  // ฟังก์ชันนี้ถูกใช้จากหน้า Product Detail
  Future<void> addOrIncrease({
    required String productId,
    required String title,
    required String platform,
    required double price,
    String? variantKey, // ✅ รับ variantKey
    int delta = 1,
  }) async {
    final user = _auth.currentUser;
    final uniqueId = 
        '$productId${variantKey != null && variantKey.isNotEmpty ? '::${variantKey}' : ''}';
        
    // --- โหมด offline (ยังไม่ล็อกอิน) ---
    if (user == null) {
      final old = _items[uniqueId];
      final nextQty = (old?.qty ?? 0) + delta;

      if (nextQty <= 0) {
        _items.remove(uniqueId);
      } else {
        _items[uniqueId] = CartItem(
          productId: productId,
          title: title,
          platform: platform,
          price: price,
          qty: nextQty.clamp(1, 999),
          variantKey: variantKey, // ✅ เก็บ variantKey
        );
      }
      notifyListeners();
      return;
    }

    // --- โหมดออนไลน์ → ให้ Firestore cap ตามสต็อกจริง ---
    // FirestoreService จะจัดการเรื่องการอัปเดต metadata ของสินค้าเอง
    await FirestoreService.instance.addToCartCapped(
      uid: user.uid,
      product: GameProduct(
        id: productId,
        title: title,
        platform: platform,
        region: '',          
        price: price,
        stock: 0,             
        images: const [],
      ),
      addQty: delta,
      variantKey: variantKey, // ✅ ส่ง variantKey ไป service
    );
  }

  /// ลดจำนวนลง 1 (ขั้นต่ำ 1; ใช้ปุ่มลบใน UI)
  Future<void> decrease(String uniqueId) async { // เปลี่ยนเป็นรับ uniqueId
    final old = _items[uniqueId];
    if (old == null) return;

    final user = _auth.currentUser;

    // offline
    if (user == null) {
      final next = (old.qty - 1);
      if (next <= 0) {
        _items.remove(uniqueId);
      } else {
        _items[uniqueId] = old.copyWith(qty: next.clamp(1, 999));
      }
      notifyListeners();
      return;
    }

    // online → ให้ service ลดแบบ cap (ใช้ uniqueId ในการค้นหา CartItem)
    await FirestoreService.instance.changeCartQtyCapped(
      uid: user.uid,
      product: GameProduct(
        id: old.productId, // ใช้ productId หลัก
        title: old.title,
        platform: old.platform,
        region: '',
        price: old.price,
        stock: 0,
        images: const [],
      ),
      delta: -1,
      variantKey: old.variantKey, // ✅ ส่ง variantKey
    );
  }

  /// ลบรายการออกจากตะกร้า
  Future<void> remove(String uniqueId) async { // เปลี่ยนเป็นรับ uniqueId
    final user = _auth.currentUser;
    final item = _items[uniqueId];

    if (item == null) return;
    
    // offline
    if (user == null) {
      _items.remove(uniqueId);
      notifyListeners();
      return;
    }
    
    // online: ต้องลบใน Firestore โดยใช้ productId + variantKey
    await FirestoreService.instance.removeCartItem(
      user.uid, 
      item.productId, 
      variantKey: item.variantKey, // ✅ ส่ง variantKey
    );
  }
  
  // (ฟังก์ชัน setAbsoluteQty ไม่ได้ใช้ใน UI ปัจจุบัน แต่ถ้าใช้จะต้องถูกแก้ไขเช่นกัน)

  @override
  void dispose() {
    _cartSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  void toOrderItemsJson() {}

  Future<void> clear() async {}
}