import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'firebase_options.dart';

// Providers
import 'providers/auth_provider.dart';
import 'providers/sales_provider.dart';
import 'providers/commission_provider.dart';
import 'providers/team_provider.dart';
import 'providers/system_config_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/customer_provider.dart';
import 'providers/leaderboard_provider.dart';
import 'providers/account_provider.dart';

// Screens
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/dashboard/sales_dashboard_screen.dart';
import 'screens/splash_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/dashboard/leaderboard_screen.dart';
import 'screens/account/account_screen.dart';

void main() async {
  try {
    WidgetsFlutterBinding.ensureInitialized();

    // 1. Initialize Firebase (Critical)
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      debugPrint("Firebase initialization failed: $e");
      // We can't do much without Firebase, but let's try to proceed 
      // or at least show the app shell so it's not a white screen.
    }

    // 2. Initialize Hive (Critical for caching)
    try {
      await Hive.initFlutter();
      await Hive.openBox('settings');
      await Hive.openBox('cache');
    } catch (e) {
      debugPrint("Hive initialization failed: $e");
    }

    runApp(const BizPOSSalesApp());
  } catch (e) {
    debugPrint("Fatal startup error: $e");
    // Fallback if everything fails
    runApp(MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('Fatal Error: $e\nPlease restart the app.'),
        ),
      ),
    ));
  }
}

// --- Firestore Helper ---
FirebaseFirestore getFirestore() => FirebaseFirestore.instance;

class BizPOSSalesApp extends StatelessWidget {
  const BizPOSSalesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => SalesAuthProvider()),
        ChangeNotifierProvider(create: (_) => SalesProvider()),
        ChangeNotifierProvider(create: (_) => CommissionProvider()),
        ChangeNotifierProvider(create: (_) => TeamProvider()),
        ChangeNotifierProvider(create: (_) => SystemConfigProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => CustomerProvider()),
        ChangeNotifierProvider(create: (_) => LeaderboardProvider()),
        ChangeNotifierProvider(create: (_) => AccountProvider()),
      ],
      child: Consumer<ThemeProvider>(
        builder: (context, themeProvider, child) {
          return MaterialApp(
            title: 'BizPOS Sales',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeProvider.themeMode,
            home: const SplashScreen(),
            routes: {
              '/login': (context) => const LoginScreen(),
              '/register': (context) => const RegisterScreen(),
              '/dashboard': (context) => const SalesDashboardScreen(),
              '/profile': (context) => const ProfileScreen(),
              '/leaderboard': (context) => const LeaderboardScreen(),
              '/account': (context) => const AccountScreen(),
            },
          );
        },
      ),
    );
  }
}
