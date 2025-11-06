import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:keyinside/features/admin/admin_dashboard_page.dart';
import 'package:keyinside/features/admin/chats/admin_chat_list_page.dart';
import 'package:keyinside/features/chat/user_chat_page.dart';
import 'package:keyinside/features/coupons/my_coupons_page.dart';
import 'package:keyinside/features/orders/my_orders_page.dart';
import 'firebase_options.dart';

import 'package:provider/provider.dart';
import 'state/cart_provider.dart';

import 'app/app_routes.dart';
import 'app/theme.dart';
import 'features/auth/login_page.dart';
import 'features/auth/profile_page.dart';
import 'features/auth/signup_page.dart';
import 'features/catalog/catalog_list_page.dart';
import 'features/catalog/product_detail_page.dart';
import 'features/cart_checkout/cart_page.dart';
import 'features/cart_checkout/checkout_page.dart';
import 'guards/auth_guard_page.dart';
import 'features/coupons/coupon_discover_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const GameKeyApp());
}

class GameKeyApp extends StatelessWidget {
  const GameKeyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // ซิงก์ตะกร้ากับ Firestore ตามผู้ใช้ที่ล็อกอิน
        ChangeNotifierProvider(create: (_) => CartProvider()),
      ],
      child: MaterialApp(
        title: 'Game Key Shop',
        theme: appTheme,
        
        themeMode: ThemeMode.system,
        debugShowCheckedModeBanner: false,

        // เส้นทางหลัก
        initialRoute: AppRoutes.catalogList,
        routes: {
          AppRoutes.userChat: (_) => const AuthGuardPage(
            requireVerified: true,
            child: UserChatPage(),
          ),
          AppRoutes.catalogList: (_) => const AuthGate(),
          AppRoutes.productDetail: (_) => const ProductDetailPage(),
          AppRoutes.cart: (_) => const CartPage(),
          AppRoutes.myOrders: (_) => const MyOrdersPage(), // 👈 เพิ่ม
          AppRoutes.checkout: (_) => const AuthGuardPage(
                 requireVerified: true,
                 child: CheckoutPage(),
),
          AppRoutes.adminDashboard: (_) => const AuthGuardPage(
             requireVerified: true,
             requireAdmin: true,
             child: AdminDashboardPage(),
      ),
          AppRoutes.adminChatList: (_) => const AuthGuardPage(
             requireVerified: true,
             requireAdmin: true,
             child: AdminChatListPage(),
  ),
          AppRoutes.login: (_) => const LoginPage(),
          AppRoutes.signup: (_) => const SignupPage(),
          AppRoutes.profile: (_) => const AuthGuardPage(child: ProfilePage()),
          AppRoutes.myCoupons: (_) => AuthGuardPage(child: MyCouponsPage()),
          AppRoutes.couponDiscover: (_) => const AuthGuardPage(
            child: CouponDiscoverPage(),
          ),
        },

      // กัน route พัง → กลับหน้า Catalog
      onUnknownRoute: (_) =>
            MaterialPageRoute(builder: (_) => const CatalogListPage()),
      ),
    );
  }
}

/// ฟัง Auth state (อนาคตเผื่อเปลี่ยนหน้าอัตโนมัติได้)
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        // ตอนนี้ให้เข้าหน้า Catalog เหมือนเดิมไม่ว่า login หรือไม่
        return const CatalogListPage();
      },
    );
  }
}
