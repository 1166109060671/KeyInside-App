import 'package:flutter/material.dart';

final ThemeData appTheme = ThemeData(
  useMaterial3: true, // ✅ ถ้าใช้ Material 3
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color.fromARGB(255, 26, 58, 52), // 💡 สีหลักของแอป (เปลี่ยนตรงนี้)
    brightness: Brightness.light,       // หรือ Brightness.dark สำหรับโหมดมืด
  ),

  // ✅ AppBar ทั่วแอป
  appBarTheme: const AppBarTheme(
    backgroundColor: Color.fromARGB(255, 26, 58, 52), // สีพื้นหลัง AppBar
    foregroundColor: Colors.white,       // สีข้อความบน AppBar
    centerTitle: false,
    elevation: 1,
  ),

  // ✅ ปุ่มทั่วแอป
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color.fromARGB(255, 32, 115, 72),
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
      textStyle: const TextStyle(fontWeight: FontWeight.bold),
    ),
  ),

  // ✅ สีพื้นหลังทั่วไป
  scaffoldBackgroundColor: const Color(0xFFF9FAFB),

  // ✅ ฟอนต์รวม (เช่น THSarabunNew)
  fontFamily: 'THSarabunNew',
);
