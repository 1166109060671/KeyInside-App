import 'package:cloud_firestore/cloud_firestore.dart';

class Coupon {
  final String id;
  final String code;
  final String description;
  final String discountType; // 'fixed' | 'percentage'
  final double discountValue;
  final double minSpend;
  final Timestamp expiryDate;

  // 🔢 ขีดจำกัดการใช้งาน
  final int usageLimitPerUser;   // 0 = ไม่จำกัดต่อคน
  final int usageLimitGlobal;    // 0 = ไม่จำกัดรวมทั้งหมด
  final int currentUsageCount;   // นับจริง ณ ตอนนี้

  Coupon({
    required this.id,
    required this.code,
    required this.description,
    required this.discountType,
    required this.discountValue,
    required this.minSpend,
    required this.expiryDate,
    this.usageLimitPerUser = 0,
    this.usageLimitGlobal = 0,
    this.currentUsageCount = 0,
  });

  bool get isPercentage => discountType == 'percentage';
  bool get isExpired => expiryDate.toDate().isBefore(DateTime.now());
  bool get isGlobalLimitReached =>
      usageLimitGlobal > 0 && currentUsageCount >= usageLimitGlobal;

  factory Coupon.fromDoc(DocumentSnapshot d) {
    final m = (d.data() as Map<String, dynamic>? ?? {});
    return Coupon(
      id: (m['id'] ?? d.id).toString(),
      code: (m['code'] ?? '').toString(),
      description: (m['description'] ?? '').toString(),
      discountType: (m['discountType'] ?? 'fixed').toString(),
      discountValue: ((m['discountValue'] ?? 0) as num).toDouble(),
      minSpend: ((m['minSpend'] ?? 0) as num).toDouble(),
      expiryDate: (m['expiryDate'] is Timestamp)
          ? m['expiryDate'] as Timestamp
          : Timestamp.fromDate(DateTime.now()),
      usageLimitPerUser: ((m['usageLimitPerUser'] ?? 0) as num).toInt(),
      usageLimitGlobal: ((m['usageLimitGlobal'] ?? 0) as num).toInt(),
      currentUsageCount: ((m['currentUsageCount'] ?? 0) as num).toInt(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'code': code,
        'description': description,
        'discountType': discountType,
        'discountValue': discountValue,
        'minSpend': minSpend,
        'expiryDate': expiryDate,
        'usageLimitPerUser': usageLimitPerUser,
        'usageLimitGlobal': usageLimitGlobal,
        'currentUsageCount': currentUsageCount,
      };

  bool get isFixed => discountType == 'fixed';
  

  /// คำนวณส่วนลด
  double calculateDiscount(double subtotal) {
    if (isExpired) return 0;
    if (subtotal < minSpend) return 0;

    if (isPercentage) {
      return (subtotal * discountValue) / 100;
    }
    if (isFixed) {
      return discountValue;
    }
    return 0;
  }
}