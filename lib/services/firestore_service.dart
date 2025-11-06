// lib/services/firestore_service.dart
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:keyinside/models/coupon.dart';

import '../models/game_product.dart';

class FirestoreService {
  FirestoreService._();
  static final instance = FirestoreService._();

  final _db = FirebaseFirestore.instance;

  // === Config สำหรับ GAS Webhook ===
  static const String kWebhookUrl =
      'https://script.google.com/macros/s/AKfycbzQ_nqM5EUDfO73YHV5RlgzUT9vtWV50oSUmXF6eY6AB7h1g20R9t-5TduWOiEyV0Mb/exec';
  static const String kSecretToken = 'myShopKey_2025_SECRET_98hf583K';

  // =====================================================
  // Helpers
  // =====================================================

  Future<DocumentReference<Map<String, dynamic>>?> _findProductDocRef(
    String anyId,
  ) async {
    final byDoc = _db.collection('products').doc(anyId);
    final docSnap = await byDoc.get();
    if (docSnap.exists) return byDoc;

    final qs = await _db
        .collection('products')
        .where('id', isEqualTo: anyId)
        .limit(1)
        .get();
    if (qs.docs.isEmpty) return null;
    return qs.docs.first.reference;
  }

  static String? _productIdOf(Map<String, dynamic> it) {
    final candidates = [it['productId'], it['productID'], it['pid'], it['id']];
    for (final c in candidates) {
      if (c is String && c.trim().isNotEmpty) return c.trim();
    }
    return null;
  }
  
  // ✅ เพิ่ม: สร้าง Doc ID สำหรับ Cart Item (Composite Key)
  static String _cartDocId(String productId, {String? variantKey}) {
    if (variantKey != null && variantKey.isNotEmpty) {
      // ใช้รูปแบบที่ปลอดภัยในการตั้งชื่อเอกสาร
      return '${productId}_${variantKey.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_')}';
    }
    return productId;
  }

  // =====================================================
  // PRODUCTS
  // =====================================================

  Stream<List<GameProduct>> streamProducts({
    String? platform,
    bool? inStockOnly,
    String? queryText,
  }) {
    Query<Map<String, dynamic>> col = _db.collection('products');

    if (platform != null && platform.isNotEmpty && platform != 'ทั้งหมด') {
      col = col.where('platform', isEqualTo: platform);
    }

    if (inStockOnly == true) {
      col = col
          .where('stock', isGreaterThan: 0) 
          .orderBy('title');
    } else {
      col = col.orderBy('title'); 
    }

    return col.snapshots().map((snap) {
      var list = snap.docs.map(GameProduct.fromDoc).toList();
      final q = (queryText ?? '').trim().toLowerCase();
      if (q.isNotEmpty) {
        list = list.where((p) => p.title.toLowerCase().contains(q)).toList();
      }
      return list;
    });
  }

  Stream<GameProduct?> streamProductById(String idOrBusinessId) async* {
    final byDoc = await _db.collection('products').doc(idOrBusinessId).get();
    if (byDoc.exists) {
      yield GameProduct.fromDoc(byDoc);
      yield* _db
          .collection('products')
          .doc(idOrBusinessId)
          .snapshots()
          .map((d) => d.exists ? GameProduct.fromDoc(d) : null);
      return;
    }

    yield* _db
        .collection('products')
        .where('id', isEqualTo: idOrBusinessId)
        .limit(1)
        .snapshots()
        .map((qs) => qs.docs.isEmpty ? null : GameProduct.fromDoc(qs.docs.first));
  }

  Future<void> upsertProduct(GameProduct p) async {
    await _db.collection('products').doc(p.id).set(
          p.toMap(),
          SetOptions(merge: true),
        );
  }

  Future<void> deleteProduct(String id) async {
    final ref = await _findProductDocRef(id);
    if (ref != null) await ref.delete();
  }

  // =====================================================
  // CART
  // =====================================================

  CollectionReference<Map<String, dynamic>> _cartCol(String uid) =>
      _db.collection('users').doc(uid).collection('cart');

  // ✅ แก้ไข: streamCart ดึง variantKey กลับมา
  Stream<List<Map<String, dynamic>>> streamCart(String uid) {
    return _cartCol(uid)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  Future<void> addToCartCapped({
    required String uid,
    required GameProduct product,
    required int addQty,
    String? variantKey, // ✅ รับ variantKey
    bool absoluteQty = false,
  }) async {
    final prodRef = await _findProductDocRef(product.id);
    if (prodRef == null) return;

    // ✅ ใช้ _cartDocId เพื่อสร้าง Document ID ที่รวม Variant Key
    final cartDocId = _cartDocId(product.id, variantKey: variantKey);
    final cartRef = _cartCol(uid).doc(cartDocId);

    await _db.runTransaction((tx) async {
      final prodSnap = await tx.get(prodRef);
      if (!prodSnap.exists) return;

      final latest = GameProduct.fromDoc(prodSnap);
      // ✅ ใช้ effective stock/price
      final stock = latest.stockFor(variantKey); 
      final price = latest.effectivePriceFor(variantKey);
      final VariantOption? variant = latest.getVariant(variantKey);

      if (stock <= 0) {
        tx.delete(cartRef);
        return;
      }

      final curSnap = await tx.get(cartRef);
      final currentQty =
          curSnap.exists ? ((curSnap.data()?['qty'] as num?) ?? 0).toInt() : 0;

      int nextQty = absoluteQty ? addQty : (currentQty + addQty);
      if (nextQty <= 0) {
        tx.delete(cartRef);
        return;
      }
      nextQty = nextQty.clamp(1, stock);
      
      // ✅ บันทึก variantKey, title และ price ที่ถูกต้องลงใน Cart Item
      final itemTitle = variant != null ? '${latest.title} (${variant.name})' : latest.title;

      tx.set(
        cartRef,
        {
          'productId': latest.id,
          'title': itemTitle,
          'platform': latest.platform,
          'price': price, // ใช้ effective price
          'qty': nextQty,
          'variantKey': variantKey, // ✅ บันทึก variantKey
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    });
  }

  Future<void> changeCartQtyCapped({
    required String uid,
    required GameProduct product,
    required int delta,
    String? variantKey, // ✅ รับ variantKey
  }) async {
    final prodRef = await _findProductDocRef(product.id);
    if (prodRef == null) return;

    // ✅ ใช้ _cartDocId เพื่อหาเอกสารที่ถูกต้อง
    final cartDocId = _cartDocId(product.id, variantKey: variantKey);
    final cartRef = _cartCol(uid).doc(cartDocId);

    await _db.runTransaction((tx) async {
      final prodSnap = await tx.get(prodRef);
      if (!prodSnap.exists) return;

      final latest = GameProduct.fromDoc(prodSnap);
      // ✅ ใช้ effective stock
      final stock = latest.stockFor(variantKey); 

      final cartSnap = await tx.get(cartRef);
      if (!cartSnap.exists) return;

      final current = (cartSnap.data()?['qty'] as num?)?.toInt() ?? 0;
      var next = current + delta;

      if (stock <= 0 || next <= 0) {
        tx.delete(cartRef);
        return;
      }
      next = next.clamp(1, stock);

      tx.update(cartRef, {
        'qty': next,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  // ✅ แก้ไข: removeCartItem รับ variantKey ด้วย
  Future<void> removeCartItem(String uid, String productId, {String? variantKey}) async {
    final cartDocId = _cartDocId(productId, variantKey: variantKey);
    await _cartCol(uid).doc(cartDocId).delete();
  }


  Future<void> clearCart(String uid) async {
    final batch = _db.batch();
    final qs = await _cartCol(uid).get();
    for (final d in qs.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }

  // =====================================================
  // ===== Coupon usage (HOLD / RELEASE / COMMIT) =====
  // =====================================================

  DocumentReference<Map<String, dynamic>> _couponUsageRef(
    String uid,
    String codeUpper,
  ) =>
      _db.collection('users').doc(uid).collection('coupon_usage').doc(codeUpper);



  Future<void> _commitCouponUsage({
    required String uid,
    required String couponCodeUpper,
    required String orderId,
  }) async {
    final ref = _couponUsageRef(uid, couponCodeUpper);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) {
        tx.set(ref, {
          'code': couponCodeUpper,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'pendingOrderIds': <String>[],
          'usedOrderIds': [orderId],
          'timesUsed': 1,
        });
        return;
      }
      tx.update(ref, {
        'pendingOrderIds': FieldValue.arrayRemove([orderId]),
        'usedOrderIds': FieldValue.arrayUnion([orderId]),
        'timesUsed': FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<bool> _isCouponHeldByUser(String uid, String couponCodeUpper) async {
    final snap = await _couponUsageRef(uid, couponCodeUpper).get();
    if (!snap.exists) return false;
    final data = snap.data()!;
    final List pending = (data['pendingOrderIds'] as List? ?? const []);
    return pending.isNotEmpty;
  }

  // =====================================================
  // ORDERS (Create from cart)  — holds coupon
  // =====================================================

  Future<String> createOrder({
    required String uid,
    required String paymentMethod,
    required String buyerName,
    required String email,
    required String note,
    required double subtotal,
    required double discount,
    String? couponCode,
  }) async {
    final ordersCol = _db.collection('orders');
    final userCartCol = _cartCol(uid);

    final cartSnap = await userCartCol.get();
    if (cartSnap.docs.isEmpty) {
      throw 'ตะกร้าของคุณว่างเปล่า';
    }

    // Cart Items ที่ถูกดึงออกมาจาก Firestore (ซึ่งถูกอัปเดต title/price/variantKey แล้วใน addToCartCapped)
    final cartItems = cartSnap.docs.map((d) {
      final data = d.data();
      return {
        'productId': data['productId'],
        'title': data['title'],
        'platform': data['platform'],
        'price': (data['price'] as num).toDouble(),
        'qty': (data['qty'] as num).toInt(),
        'variantKey': data['variantKey'], // ✅ เพิ่ม variantKey
        'images': data['images'] ?? [], // ใช้ images จาก product หลัก (ยังไม่มี)
      };
    }).toList();

    double calculatedSubtotal = 0;
    for (final it in cartItems) {
      calculatedSubtotal += (it['price'] as double) * (it['qty'] as int);
    }

    final double grandTotal =
        (calculatedSubtotal - discount).clamp(0, calculatedSubtotal);

    final orderRef = ordersCol.doc();
    final String? codeUpper =
        (couponCode == null || couponCode.trim().isEmpty)
            ? null
            : couponCode.trim().toUpperCase();

    await _db.runTransaction((tx) async {
      // กันใช้คูปองซ้ำถ้ามี hold อยู่แล้ว
      if (codeUpper != null) {
        final usageRef = _couponUsageRef(uid, codeUpper);
        final usageSnap = await tx.get(usageRef);
        final List pending = usageSnap.exists
            ? ((usageSnap.data()?['pendingOrderIds'] as List?) ?? const [])
            : const [];
        if (pending.isNotEmpty) {
          throw 'คุณมีออเดอร์ที่ยังใช้คูปองนี้อยู่ กรุณารอการตรวจสอบหรือยกเลิกก่อน';
        }
      }

      // สร้างออเดอร์ (pending)
      tx.set(orderRef, {
        'orderId': orderRef.id,
        'uid': uid,
        'status': 'pending',
        'paymentMethod': paymentMethod,
        'buyerName': buyerName,
        'email': email,
        'note': note,
        'total': grandTotal,
        'amount': grandTotal,
        'items': cartItems,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'stockAdjusted': false,
        'restocked': false,
        'subtotal': subtotal,
        'discount': discount,
        'couponCode': codeUpper,
      });

      // จองสิทธิ์คูปอง (HOLD) ใน usage ของผู้ใช้
      if (codeUpper != null) {
        tx.set(_couponUsageRef(uid, codeUpper), {
          'code': codeUpper,
          'pendingOrderIds': FieldValue.arrayUnion([orderRef.id]),
          'timesUsed': FieldValue.increment(0),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }

      // ล้างตะกร้า
      for (final d in cartSnap.docs) {
        tx.delete(d.reference);
      }
    });

    return orderRef.id;
  }

  // =====================================================
  // ORDERS (Admin/User actions)
  // =====================================================

  Stream<List<Map<String, dynamic>>> streamOrders({
    String status = 'all',
    int limit = 200,
    String? searchText,
  }) {
    final CollectionReference<Map<String, dynamic>> col =
        _db.collection('orders');

    Query<Map<String, dynamic>> q = (status == 'all')
        ? col.orderBy('createdAt', descending: true)
        : col.where('status', isEqualTo: status).orderBy('createdAt', descending: true);

    return q.limit(limit).snapshots().map((snap) {
      final raw = snap.docs.map((d) {
        final data = d.data();
        final orderId = (data['orderId'] ?? data['id'] ?? d.id).toString();
        final totalNum = (data['total'] ?? data['amount'] ?? 0);
        final total = totalNum is num ? totalNum.toDouble() : 0.0;

        return <String, dynamic>{
          ...data,
          'docId': d.id,
          'orderId': orderId,
          'total': total,
        };
      }).toList();

      if (searchText != null && searchText.trim().isNotEmpty) {
        final s = searchText.toLowerCase().trim();
        return raw.where((o) {
          final oid = (o['orderId'] ?? '').toString().toLowerCase();
          final email = (o['email'] ?? '').toString().toLowerCase();
          return oid.contains(s) || email.contains(s);
        }).toList();
      }

      return raw;
    });
  }

  Future<Map<String, dynamic>?> getOrder(String orderId) async {
    var doc = await _db.collection('orders').doc(orderId).get();

    if (!doc.exists) {
      final qs = await _db
          .collection('orders')
          .where('orderId', isEqualTo: orderId)
          .limit(1)
          .get();
      if (qs.docs.isEmpty) return null;
      doc = qs.docs.first;
    }

    final data = doc.data();
    if (data == null) return null;

    final totalNum = (data['total'] ?? data['amount'] ?? 0);
    final total = totalNum is num ? totalNum.toDouble() : 0.0;

    return {
      ...data,
      'docId': doc.id,
      'orderId': (data['orderId'] ?? data['id'] ?? doc.id).toString(),
      'total': total,
    };
  }

  // =====================================================
  // Status updates / Stock-aware + COUPON usage commit
  // =====================================================

  Future<void> updateOrderStatus({
    required String orderId,
    required String nextStatus,
    String? cancelReason,
  }) async {
    final ref = _db.collection('orders').doc(orderId);
    final patch = <String, dynamic>{
      'status': nextStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (nextStatus == 'cancelled') {
      if ((cancelReason ?? '').trim().isNotEmpty) {
        patch['cancelReason'] = cancelReason!.trim();
      } else {
        patch['cancelReason'] = FieldValue.delete();
      }
    } else {
      patch['cancelReason'] = FieldValue.delete();
    }
    await ref.set(patch, SetOptions(merge: true));
  }
  
  // ✅ แก้ไข: markOrderPaid เพื่อรองรับการตรวจสอบ Variant Stock และหัก Base Stock
  Future<void> markOrderPaid(String orderId) async {
    await _db.runTransaction((tx) async {
      final orderRef = _db.collection('orders').doc(orderId);
      final orderSnap = await tx.get(orderRef);
      if (!orderSnap.exists) throw 'ไม่พบคำสั่งซื้อ';

      final data = orderSnap.data() as Map<String, dynamic>;
      final status = (data['status'] ?? 'pending').toString().toLowerCase();
      final adjusted = (data['stockAdjusted'] ?? false) == true;

      if (status == 'cancelled') {
        throw 'ออเดอร์ถูกยกเลิกแล้ว';
      }
      if (status == 'paid' && adjusted) {
        // เคลียร์ hold เผื่อค้าง
        final code = (data['couponCode'] ?? '').toString();
        final uid = (data['uid'] ?? '').toString();
        if (code.isNotEmpty && uid.isNotEmpty) {
          tx.set(_couponUsageRef(uid, code.toUpperCase()), {
            'pendingOrderIds': FieldValue.arrayRemove([orderId]),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }
        return;
      }

      // — ตรวจสต๊อก —
      final items = (data['items'] as List? ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();

      // โครงสร้างสำหรับเก็บความต้องการสต๊อก: {ProductDocRef: {VariantKey: Qty}}
      final Map<DocumentReference, Map<String?, int>> want = {};
      for (final it in items) {
        final pid = _productIdOf(it);
        final variantKey = (it['variantKey'] ?? '').toString();
        final finalVariantKey = variantKey.isEmpty ? null : variantKey;
        final qty = ((it['qty'] ?? 0) as num).toInt();
        if (pid == null || qty <= 0) continue;
        
        final prodRef = _db.collection('products').doc(pid);
        want.putIfAbsent(prodRef, () => {});
        want[prodRef]![finalVariantKey] = (want[prodRef]![finalVariantKey] ?? 0) + qty;
      }
      
      // 🚀 ตรวจและหักสต๊อก (ใช้ Transaction)
      for (final e in want.entries) {
        final prodRef = e.key;
        final variantsWanted = e.value;
        final ps = await tx.get(prodRef) as DocumentSnapshot<Map<String, dynamic>>;
        if (!ps.exists) throw 'ไม่พบสินค้า ${prodRef.id}';
        
        final latest = GameProduct.fromDoc(ps);
        
        // 💡 เราจะใช้ Map สำหรับอัปเดต Base Stock และ Variants (ถ้ามี)
        final Map<String, dynamic> productPatch = {};
        
        // **ต้องอ่าน Map variants ทั้งก้อนมาแก้ไขหากมีการหัก Variant Stock**
        Map<String, dynamic> currentVariantsMap = latest.variants.map((k, v) => MapEntry(k, v.toMap()));
        
        int totalSoldCount = 0;
        int totalQtyToDecrement = 0; // ✅ เพิ่ม: สำหรับ Base Stock

        variantsWanted.forEach((variantKey, requiredQty) {
          final currentStock = latest.stockFor(variantKey);
          
          if (currentStock < requiredQty) {
              final name = variantKey == null 
                  ? latest.title 
                  : latest.getVariant(variantKey)?.name ?? latest.title;
              throw 'สต๊อกไม่พอสำหรับ $name (ต้องการ $requiredQty, คงเหลือ $currentStock)';
          }
          
          totalSoldCount += requiredQty;
          
          final variantOption = latest.getVariant(variantKey);

          // ✅ Logic หัก: หัก Variant Stock (ถ้ามี override) หรือหัก Base Stock
          if (variantKey != null && variantOption?.stock != null) {
              // 1. หัก Variant Stock โดยตรง
              final vKey = variantKey;
              final currentVariantData = currentVariantsMap[vKey] as Map<String, dynamic>?;
              
              if (currentVariantData != null) {
                  final newVariantStock = currentStock - requiredQty;
                  currentVariantData['stock'] = newVariantStock;
              } 
              // 💡 Base Stock ไม่ต้องหักถ้ามี Variant Stock Override
              
          } else {
              // 2. หัก Base Stock (Stock ตัวธรรมดา)
              totalQtyToDecrement += requiredQty; // ✅ รวม Qty ที่ต้องหัก Base Stock
          }
        });
        
        // 🚀 เขียนทับ Variants Map ถ้ามีการหัก Variant Stock
        if (latest.hasVariants) {
            productPatch['variants'] = currentVariantsMap;
        }

        // 3. อัปเดต Base Stock และ Sold Count โดยใช้ FieldValue.increment เพียงครั้งเดียว
        if (totalQtyToDecrement > 0) {
          productPatch['stock'] = FieldValue.increment(-totalQtyToDecrement);
        }
        
        productPatch['sold'] = FieldValue.increment(totalSoldCount); // ใช้ totalSoldCount ที่เป็น int
        
        // ดำเนินการอัปเดต
        tx.update(prodRef, {
            ...productPatch,
            'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      
      // ... (โค้ดอัปเดต Order Status และ Coupon Logic เหมือนเดิม) ...
      tx.update(orderRef, {
        'status': 'paid',
        'stockAdjusted': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      

      // ✅ ยืนยันการใช้คูปองจริง: +1 global และย้ายจาก hold → used (per user)
      final code = (data['couponCode'] ?? '').toString();
      final uid = (data['uid'] ?? '').toString();
      if (code.isNotEmpty && uid.isNotEmpty) {
        final codeUpper = code.toUpperCase();

        // 1) เพิ่ม usage จริงใน collection coupons
        final qs = await _db
            .collection('coupons')
            .where('code', isEqualTo: codeUpper)
            .limit(1)
            .get();
        if (qs.docs.isNotEmpty) {
          tx.update(qs.docs.first.reference, {
            'currentUsageCount': FieldValue.increment(1),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }

        // 2) อัปเดต usage ฝั่งผู้ใช้: ลบ hold
        tx.set(_couponUsageRef(uid, codeUpper), {
          'pendingOrderIds': FieldValue.arrayRemove([orderId]),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    });

    // นอก txn: บันทึกว่า “used” ในเอกสาร usage (เก็บ history/นับ timesUsed)
    final data = await getOrder(orderId);
    final code = (data?['couponCode'] ?? '').toString();
    final uid = (data?['uid'] ?? '').toString();
    if (code.isNotEmpty && uid.isNotEmpty) {
      await _commitCouponUsage(
        uid: uid,
        couponCodeUpper: code.toUpperCase(),
        orderId: orderId,
      );
    }
  }

  // ✅ แก้ไข: cancelOrder เพื่อรองรับการคืน Base Stock
  Future<void> cancelOrder(String orderId, {String? reason}) async {
    await _db.runTransaction((tx) async {
      final orderRef = _db.collection('orders').doc(orderId);
      final orderSnap = await tx.get(orderRef);
      if (!orderSnap.exists) throw 'ไม่พบคำสั่งซื้อ';

      final data = orderSnap.data() as Map<String, dynamic>;
      final adjusted = (data['stockAdjusted'] ?? false) == true;
      final restocked = (data['restocked'] ?? false) == true;

      // คืนสต๊อกถ้าหักไปแล้ว
      if (adjusted && !restocked) {
        final items = (data['items'] as List? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList();

        final Map<DocumentReference, Map<String?, int>> giveBack = {};
        for (final it in items) {
          final pid = _productIdOf(it);
          final variantKey = (it['variantKey'] ?? '').toString();
          final finalVariantKey = variantKey.isEmpty ? null : variantKey;
          final qty = ((it['qty'] ?? 0) as num).toInt();
          if (pid == null || qty <= 0) continue;
          
          final prodRef = _db.collection('products').doc(pid);
          giveBack.putIfAbsent(prodRef, () => {});
          giveBack[prodRef]![finalVariantKey] = (giveBack[prodRef]![finalVariantKey] ?? 0) + qty;
        }

        // 🚀 คืนสต๊อก (Base Stock และ Variant Stock)
        for (final e in giveBack.entries) {
          final prodRef = e.key;
          final variantsToRestore = e.value;
          final ps = await tx.get(prodRef) as DocumentSnapshot<Map<String, dynamic>>;
          if (!ps.exists) continue; 
          
          final latest = GameProduct.fromDoc(ps);
          final Map<String, dynamic> productPatch = {};
          Map<String, dynamic> currentVariantsMap = latest.variants.map((k, v) => MapEntry(k, v.toMap()));
          
          int totalRestoreCount = 0;
          int totalQtyToIncrement = 0; // ✅ เพิ่ม: สำหรับ Base Stock

          variantsToRestore.forEach((variantKey, requiredQty) {
              totalRestoreCount += requiredQty;
              final variantOption = latest.getVariant(variantKey);
              
              if (variantKey != null && variantOption?.stock != null) {
                  // 1. คืน Variant Stock
                  final vKey = variantKey;
                  final currentVariantData = currentVariantsMap[vKey] as Map<String, dynamic>?;
                  
                  if (currentVariantData != null) {
                      final currentStock = latest.stockFor(variantKey);
                      final newVariantStock = currentStock + requiredQty;
                      currentVariantData['stock'] = newVariantStock;
                  }
                  // 💡 ถ้ามี Variant Stock, Base Stock ไม่ต้องคืน
              } else {
                  // 2. คืน Base Stock
                  totalQtyToIncrement += requiredQty; // ✅ รวม Qty ที่ต้องคืน Base Stock
              }
            });
          
          // 3. เขียนทับ Variants Map และคืน Sold Count
          if (latest.hasVariants) {
              productPatch['variants'] = currentVariantsMap;
          }
          
          // 4. อัปเดต Base Stock และ Sold
          if (totalQtyToIncrement > 0) {
            productPatch['stock'] = FieldValue.increment(totalQtyToIncrement);
          }
          
          productPatch['sold'] = FieldValue.increment(-totalRestoreCount);

          tx.update(prodRef, {
            ...productPatch,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        // 💡 สิ้นสุดส่วนคืนสต็อก

        tx.update(orderRef, {
          'status': 'cancelled',
          'cancelReason':
              (reason ?? '').trim().isNotEmpty ? reason!.trim() : FieldValue.delete(),
          'restocked': true,
          'cancelledAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        tx.update(orderRef, {
          'status': 'cancelled',
          'cancelReason':
              (reason ?? '').trim().isNotEmpty ? reason!.trim() : FieldValue.delete(),
          'cancelledAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }

      // ปล่อยสิทธิ์คูปอง (ลบ hold) ถ้ามี
      final code = (data['couponCode'] ?? '').toString();
      final uid = (data['uid'] ?? '').toString();
      if (code.isNotEmpty && uid.isNotEmpty) {
        tx.set(_couponUsageRef(uid, code.toUpperCase()), {
          'pendingOrderIds': FieldValue.arrayRemove([orderId]),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    });
  }

  // =====================================================
  // (โค้ดส่วนอื่น ๆ ยังคงเดิม)
  // =====================================================


  // ===== Random Key Generator (ตัด I,O,0,1) =====
  String _randKey({int parts = 3, int len = 5}) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    var seed = DateTime.now().microsecondsSinceEpoch;
    String pick() {
      seed = 0x5DEECE66D * seed + 0xB;
      final i = (seed & 0x7fffffff) % chars.length;
      return chars[i];
    }
    final sections =
        List.generate(parts, (_) => List.generate(len, (_) => pick()).join());
    return sections.join('-'); // เช่น 0GK6W-Q57X2-RZ97A
  }

  Future<void> generateKeysForOrder(String orderId) async {
    final ref = _db.collection('orders').doc(orderId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw 'ไม่พบคำสั่งซื้อ';

      final data = snap.data() as Map<String, dynamic>;
      final items = (data['items'] as List? ?? const [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      bool changed = false;
      for (final it in items) {
        final qty = ((it['qty'] ?? 0) as num).toInt();
        final keys =
            (it['keys'] as List?)?.whereType<String>().toList() ?? <String>[];
        final need = qty - keys.length;
        if (need > 0) {
          for (int i = 0; i < need; i++) {
            keys.add(_randKey());
          }
          it['keys'] = keys;
          changed = true;
        }
      }

      if (changed) {
        tx.update(ref, {
          'items': items,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
  }

  // =====================================================
  // Email via GAS Webhook — รอ keys ให้ครบก่อน
  // =====================================================

  int _needKeysCount(Map<String, dynamic> order) {
    final items = (order['items'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
    int need = 0;
    for (final it in items) {
      final qty = ((it['qty'] ?? 0) as num).toInt();
      final keys =
          (it['keys'] as List?)?.whereType<String>().toList() ?? const [];
      final missing = qty - keys.length;
      if (missing > 0) need += missing;
    }
    return need;
  }

  Future<Map<String, dynamic>> _ensureKeysReady(String orderId) async {
    final ref = _db.collection('orders').doc(orderId);

    Future<Map<String, dynamic>> readOnce() async {
      final snap = await ref.get(const GetOptions(source: Source.server));
      if (!snap.exists) throw 'ไม่พบคำสั่งซื้อ $orderId';
      return Map<String, dynamic>.from(snap.data()!);
    }

    const maxTries = 8;
    var delay = const Duration(milliseconds: 200);
    Map<String, dynamic> data = {};
    for (var i = 0; i < maxTries; i++) {
      data = await readOnce();
      if (_needKeysCount(data) == 0) return data;
      await Future.delayed(delay);
      delay = Duration(milliseconds: (delay.inMilliseconds * 1.5).round());
    }

    await generateKeysForOrder(orderId);

    delay = const Duration(milliseconds: 250);
    for (var i = 0; i < 6; i++) {
      data = await readOnce();
      if (_needKeysCount(data) == 0) return data;
      await Future.delayed(delay);
      delay = Duration(milliseconds: (delay.inMilliseconds * 1.5).round());
    }

    return data;
  }

  Future<void> sendKeysEmailViaWebhook({
    required String orderId,
    required String webhookUrl, // /exec
    required String token, // ต้องตรงกับ SECRET_TOKEN ใน GAS
    bool quiet = false, // true = ไม่โยน error ออก UI
  }) async {
    final data = await _ensureKeysReady(orderId);

    final totalRaw = (data['total'] ?? data['amount'] ?? 0);
    final payload = {
      'token': token,
      'orderId': (data['orderId'] ?? orderId).toString(),
      'buyerName': (data['buyerName'] ?? '').toString(),
      'email': (data['email'] ?? '').toString(),
      'items': (data['items'] ?? []),
      'total': totalRaw is num ? totalRaw.toDouble() : 0.0,
    };
    final body = jsonEncode(payload);

    final ref = _db.collection('orders').doc(orderId);

    final client = HttpClient()..autoUncompress = true;
    Uri current = Uri.parse(webhookUrl);
    int hops = 0;

    while (true) {
      final req = await client.postUrl(current);
      req.headers.set('content-type', 'application/json; charset=utf-8');
      req.headers.set('accept', 'application/json, */*');
      req.followRedirects = false;
      req.add(utf8.encode(body));

      final res = await req.close();
      final status = res.statusCode;

      if (status >= 200 && status < 300) {
        await ref.set({
          'emailWebhook': {
            'ok': true,
            'statusCode': status,
            'emailedAt': FieldValue.serverTimestamp(),
          }
        }, SetOptions(merge: true));
        client.close(force: true);
        return;
      }

      final loc = res.headers.value('location');
      if ((status == 301 ||
              status == 302 ||
              status == 303 ||
              status == 307 ||
              status == 308) &&
          loc != null &&
          hops < 5) {
        current = _resolveRedirect(current, loc);
        hops++;
        continue;
      }

      final text = await _safeReadText(res);

      await ref.set({
        'emailWebhook': {
          'ok': false,
          'statusCode': status,
          'error': text,
          'at': FieldValue.serverTimestamp(),
        }
      }, SetOptions(merge: true));

      client.close(force: true);
      if (quiet) return;
      throw 'Webhook error $status: $text';
    }
  }

  Future<String> _safeReadText(HttpClientResponse res) async {
    try {
      return await res.transform(const Utf8Decoder(allowMalformed: true)).join();
    } catch (_) {
      final bytes = <int>[];
      await for (final chunk in res) {
        bytes.addAll(chunk);
      }
      return latin1.decode(bytes, allowInvalid: true);
    }
  }

  Uri _resolveRedirect(Uri base, String location) {
    final locUri = Uri.parse(location);
    if (locUri.isAbsolute) {
      return locUri;
    } else {
      return base.resolveUri(locUri);
    }
  }

  // =====================================================
  // COUPONS
  // =====================================================

  Stream<List<Coupon>> streamCoupons() {
    return _db
        .collection('coupons')
        .where('expiryDate', isGreaterThanOrEqualTo: Timestamp.now())
        .orderBy('expiryDate', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map(Coupon.fromDoc).toList());
  }

  Future<void> deleteCoupon(String id) async {
    await _db.collection('coupons').doc(id).delete();
  }

  /// เช็กว่า user เคยใช้คูปองนี้ไปแล้วหรือยัง (นับ pending + paid)
  Future<bool> hasUserUsedCouponOnce(String uid, String couponCode) async {
    final q = await _db
        .collection('orders')
        .where('uid', isEqualTo: uid)
        .where('couponCode', isEqualTo: couponCode)
        .where('status', whereIn: ['pending', 'paid'])
        .limit(1)
        .get();
    return q.docs.isNotEmpty;
  }

  /// ใช้ก่อน apply คูปอง: ตรวจหมดอายุ/ขั้นต่ำ/โควต้า + มี hold อยู่ไหม
  Future<Coupon> validateCoupon(String uid, String code, double subtotal) async {
    if (code.trim().isEmpty) {
      throw 'กรุณากรอกโค้ดคูปอง';
    }

    final now = Timestamp.now();
    final codeUpper = code.trim().toUpperCase();

    final qs = await _db
        .collection('coupons')
        .where('code', isEqualTo: codeUpper)
        .limit(1)
        .get();

    if (qs.docs.isEmpty) {
      throw 'ไม่พบคูปอง “$codeUpper”';
    }

    final coupon = Coupon.fromDoc(qs.docs.first);

    if (coupon.expiryDate.toDate().isBefore(now.toDate())) {
      throw 'คูปอง “$codeUpper” หมดอายุแล้ว';
    }

    if (subtotal < coupon.minSpend) {
      throw 'ยอดซื้อขั้นต่ำ ฿${coupon.minSpend.toStringAsFixed(0)} (ยอดปัจจุบัน ฿${subtotal.toStringAsFixed(2)})';
    }

    // Global limit
    if (coupon.isGlobalLimitReached) {
      throw 'คูปอง “$codeUpper” ถูกใช้จนครบจำนวนจำกัดแล้ว';
    }

    // Per-user limit (จาก orders)
    if (coupon.usageLimitPerUser > 0) {
      final used = await hasUserUsedCouponOnce(uid, coupon.code);
      if (used) {
        throw 'คูปอง “$codeUpper” ถูกจำกัดการใช้ที่ ${coupon.usageLimitPerUser} ครั้งต่อผู้ใช้';
      }
    }

    // กันใช้ซ้ำระหว่าง pending (ดูที่ coupon_usage)
    final held = await _isCouponHeldByUser(uid, codeUpper);
    if (held) {
      throw 'คุณมีออเดอร์ที่ยังใช้คูปองนี้อยู่';
    }

    return coupon;
  }

  /// คูปองที่ผู้ใช้กดรับมาเก็บไว้
  Stream<List<Coupon>> streamMyClaimedCoupons(String uid) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('my_coupons')
        .orderBy('claimedAt', descending: true)
        .snapshots()
        .asyncMap((myCouponsSnap) async {
      final couponIds = myCouponsSnap.docs.map((doc) => doc.id).toList();

      if (couponIds.isEmpty) return <Coupon>[];

      final couponDocs = await _db
          .collection('coupons')
          .where(FieldPath.documentId, whereIn: couponIds.take(30).toList())
          .get();

      final coupons =
          couponDocs.docs.map(Coupon.fromDoc).where((c) => !c.isExpired).toList();

      // เรียงตามลำดับที่รับล่าสุด
      coupons.sort((a, b) => couponIds.indexOf(a.id).compareTo(couponIds.indexOf(b.id)));

      return coupons;
    });
  }

  /// ผู้ใช้กดรับคูปองมาเก็บไว้
  Future<void> claimCoupon(String uid, Coupon coupon) async {
    if (coupon.isExpired) {
      throw 'คูปองนี้หมดอายุแล้ว';
    }

    final docRef =
        _db.collection('users').doc(uid).collection('my_coupons').doc(coupon.id);

    final snap = await docRef.get();
    if (snap.exists) {
      throw 'คุณกดรับคูปองนี้ไปแล้ว';
    }

    await docRef.set({
      'couponId': coupon.id,
      'claimedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> upsertCoupon(String id, Map<String, dynamic> data) async {
    await _db.collection('coupons').doc(id).set(data, SetOptions(merge: true));
  }
}

// ======================= CHATS (Admin & User) =======================
extension ChatApi on FirestoreService {
  CollectionReference<Map<String, dynamic>> get _chats => _db.collection('chats');
  CollectionReference<Map<String, dynamic>> _msgs(String uid) =>
      _chats.doc(uid).collection('messages');

  // ---------- Room ----------
  Future<void> ensureChatRoom(String uid) async {
    final doc = _chats.doc(uid);
    final snap = await doc.get();

    if (!snap.exists) {
      await doc.set({
        'roomId': uid,
        'participants': [uid, 'admin'],
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'lastAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
        'lastSender': '',
        'unreadForUser': 0,
        'unreadForAdmin': 0,
      });
    } else {
      final data = snap.data() ?? {};
      final participants = data['participants'] as List?;
      if (participants == null ||
          !participants.contains('admin') ||
          !participants.contains(uid)) {
        await doc.set({
          'participants': FieldValue.arrayUnion([uid, 'admin']),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }
  }

  // ---------- Streams ----------
  Stream<List<Map<String, dynamic>>> streamAllChatsForAdmin() {
    return _chats
        .where('participants', arrayContains: 'admin')
        .orderBy('updatedAt', descending: true)
        .limit(200)
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  Stream<List<Map<String, dynamic>>> streamMessages(String uid) {
    return _msgs(uid)
        .orderBy('createdAt', descending: false)
        .limit(200)
        .snapshots()
        .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  // ---------- Send text ----------
  Future<void> sendChatMessage({
    required String roomUid,
    required String senderId,
    required String text,
  }) async {
    await ensureChatRoom(roomUid);
    final ref = _msgs(roomUid).doc();
    final now = FieldValue.serverTimestamp();
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    await _db.runTransaction((tx) async {
      tx.set(ref, {
        'id': ref.id,
        'type': 'text',
        'text': trimmed,
        'senderId': senderId,
        'from': senderId,
        'createdAt': now,
        'readBy': [senderId],
        'readByUser': senderId != 'admin',
        'readByAdmin': senderId == 'admin',
      });

      final forUser = senderId == 'admin' ? 1 : 0;
      final forAdmin = senderId == 'admin' ? 0 : 1;

      tx.set(_chats.doc(roomUid), {
        'lastMessage': trimmed,
        'lastSender': senderId,
        'lastMessageAt': now,
        'lastAt': now,
        'updatedAt': now,
        'unreadForUser': FieldValue.increment(forUser),
        'unreadForAdmin': FieldValue.increment(forAdmin),
        'participants': FieldValue.arrayUnion([roomUid, 'admin']),
      }, SetOptions(merge: true));
    });
  }

  // ---------- Send Image (single) ----------
  Future<void> sendSingleImageMessage({
    required String roomUid,
    required String senderId,
    required String base64Image,
  }) async {
    if (base64Image.isEmpty) return;
    await ensureChatRoom(roomUid);
    final ref = _msgs(roomUid).doc();
    final now = FieldValue.serverTimestamp();

    await _db.runTransaction((tx) async {
      tx.set(ref, {
        'id': ref.id,
        'type': 'image',
        'image': base64Image,
        'senderId': senderId,
        'from': senderId,
        'createdAt': now,
        'readBy': [senderId],
        'readByUser': senderId != 'admin',
        'readByAdmin': senderId == 'admin',
      });

      final forUser = senderId == 'admin' ? 1 : 0;
      final forAdmin = senderId == 'admin' ? 0 : 1;
      const message = '📸 ส่งรูป 1 รูป';

      tx.set(_chats.doc(roomUid), {
        'lastMessage': message,
        'lastSender': senderId,
        'lastMessageAt': now,
        'lastAt': now,
        'updatedAt': now,
        'unreadForUser': FieldValue.increment(forUser),
        'unreadForAdmin': FieldValue.increment(forAdmin),
        'participants': FieldValue.arrayUnion([roomUid, 'admin']),
      }, SetOptions(merge: true));
    });
  }

  // ---------- Send Image (plural) ----------
  Future<void> sendPluralImageMessage({
    required String roomUid,
    required String senderId,
    required List<String> base64Images,
  }) async {
    if (base64Images.isEmpty) return;
    await ensureChatRoom(roomUid);
    final ref = _msgs(roomUid).doc();
    final now = FieldValue.serverTimestamp();

    await _db.runTransaction((tx) async {
      tx.set(ref, {
        'id': ref.id,
        'type': 'images',
        'images': base64Images,
        'senderId': senderId,
        'from': senderId,
        'createdAt': now,
        'readBy': [senderId],
        'readByUser': senderId != 'admin',
        'readByAdmin': senderId == 'admin',
      });

      final forUser = senderId == 'admin' ? 1 : 0;
      final forAdmin = senderId == 'admin' ? 0 : 1;
      final message = '📸 ส่งรูป ${base64Images.length} รูป';

      tx.set(_chats.doc(roomUid), {
        'lastMessage': message,
        'lastSender': senderId,
        'lastMessageAt': now,
        'lastAt': now,
        'updatedAt': now,
        'unreadForUser': FieldValue.increment(forUser),
        'unreadForAdmin': FieldValue.increment(forAdmin),
        'participants': FieldValue.arrayUnion([roomUid, 'admin']),
      }, SetOptions(merge: true));
    });
  }

  // ---------- Read receipts ----------
  Future<void> markChatRead({
    required String roomUid,
    required String readerId, // 'admin' หรือ uid
    int limit = 50,
  }) async {
    final roomRef = _chats.doc(roomUid);

    await roomRef.set(
      readerId == 'admin'
          ? {
              'unreadForAdmin': 0,
              'updatedAt': FieldValue.serverTimestamp(),
            }
          : {
              'unreadForUser': 0,
              'updatedAt': FieldValue.serverTimestamp(),
            },
      SetOptions(merge: true),
    );

    final snap = await _msgs(roomUid)
        .where('senderId', isNotEqualTo: readerId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();

    final batch = _db.batch();
    int updatedCount = 0;
    for (final d in snap.docs) {
      final m = d.data();
      final sender = (m['senderId'] ?? '').toString();
      final List readBy = (m['readBy'] as List? ?? const []);
      if (sender != readerId && !readBy.contains(readerId)) {
        batch.update(d.reference, {
          'readBy': FieldValue.arrayUnion([readerId]),
          if (readerId == 'admin') 'readByAdmin': true,
          if (readerId != 'admin') 'readByUser': true,
        });
        updatedCount++;
      }
    }
    if (updatedCount > 0) {
      await batch.commit();
    }
  }

  // ---------- Helpers (User) ----------
  Future<void> sendUserText({required String uid, required String text}) async {
    await sendChatMessage(roomUid: uid, senderId: uid, text: text);
  }

  // ✅ เพิ่มฟังก์ชันนี้สำหรับส่งรูปเดียว (ใช้ใน user_chat_page)
  Future<void> sendUserImage({
    required String uid,
    required String base64Image,
  }) async {
    await sendSingleImageMessage(roomUid: uid, senderId: uid, base64Image: base64Image);
  }

  // ✅ เพิ่มฟังก์ชันนี้สำหรับส่งหลายรูป (ใช้ใน user_chat_page)
  Future<void> sendUserImages({
    required String uid,
    required List<String> base64Images,
  }) async {
    await sendPluralImageMessage(roomUid: uid, senderId: uid, base64Images: base64Images);
  }
  
  // ---------- Helpers (Admin) ----------
  Future<void> sendAdminMessage({
    required String toUid,
    required String text,
  }) async {
    await sendChatMessage(roomUid: toUid, senderId: 'admin', text: text);
  }

  // ✅ เพิ่มฟังก์ชันนี้สำหรับส่งรูปเดียว (ใช้ใน admin_chat_room_page)
  Future<void> sendAdminImage({
    required String toUid,
    required String base64Image,
  }) async {
    await sendSingleImageMessage(roomUid: toUid, senderId: 'admin', base64Image: base64Image);
  }

  // ✅ เพิ่มฟังก์ชันนี้สำหรับส่งหลายรูป (ใช้ใน admin_chat_room_page)
  Future<void> sendAdminImages({
    required String toUid,
    required List<String> base64Images,
  }) async {
    await sendPluralImageMessage(roomUid: toUid, senderId: 'admin', base64Images: base64Images);
  }

  Future<Map<String, String>> getUserBrief(String uid) async {
    final doc = await _db.collection('users').doc(uid).get();
    final m = (doc.data() ?? {});
    return {
      'displayName': (m['displayName'] ?? m['name'] ?? m['email'] ?? uid).toString(),
      'photoB64': (m['photoB64'] ?? '').toString(),
      'email': (m['email'] ?? '').toString(),
    };
  }
}
