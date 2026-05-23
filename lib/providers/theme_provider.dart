import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';

class ThemeProvider with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  static const String _themeKey = 'theme_mode';

  ThemeMode get themeMode => _themeMode;
  bool get isDarkMode => _themeMode == ThemeMode.dark;

  ThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeStr = prefs.getString(_themeKey);
    if (themeStr == 'light') {
      _themeMode = ThemeMode.light;
    } else if (themeStr == 'dark') {
      _themeMode = ThemeMode.dark;
    } else {
      _themeMode = ThemeMode.system;
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    String modeStr = 'system';
    if (mode == ThemeMode.light) modeStr = 'light';
    if (mode == ThemeMode.dark) modeStr = 'dark';
    await prefs.setString(_themeKey, modeStr);
    notifyListeners();
  }

  void toggleTheme() {
    if (_themeMode == ThemeMode.light) {
      setThemeMode(ThemeMode.dark);
    } else {
      setThemeMode(ThemeMode.light);
    }
  }
}

class AppTheme {
  // Brand Colors
  static const Color primaryBlue = Color(0xFF1E3A8A); // Blue 900
  static const Color accentCyan = Color(0xFF00ACC1);
  static const Color slate50 = Color(0xFFF8FAFC);
  static const Color slate100 = Color(0xFFF1F5F9);
  static const Color slate800 = Color(0xFF1E293B);
  static const Color slate900 = Color(0xFF0F172A);
  static const Color sky400 = Color(0xFF38BDF8);

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryBlue,
      primary: primaryBlue,
      secondary: accentCyan,
      surface: Colors.white,
      background: slate50,
      onBackground: slate900,
      onSurface: slate900,
    ),
    scaffoldBackgroundColor: slate50,
    textTheme: GoogleFonts.outfitTextTheme(ThemeData.light().textTheme).copyWith(
      displayLarge: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: slate900),
      titleLarge: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: slate900),
      bodyLarge: GoogleFonts.outfit(color: slate900),
      bodyMedium: GoogleFonts.outfit(color: slate800),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: primaryBlue,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
    ),
    cardTheme: CardTheme(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: slate200, width: 1),
      ),
      margin: const EdgeInsets.only(bottom: 12),
    ),
    dividerTheme: DividerThemeData(color: slate200, thickness: 1),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );

  static Color get slate200 => const Color(0xFFE2E8F0);
  static Color get slate700 => const Color(0xFF334155);

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: sky400,
      brightness: Brightness.dark,
      primary: sky400,
      secondary: accentCyan,
      surface: slate800,
      background: slate900,
      onBackground: slate50,
      onSurface: slate50,
    ),
    scaffoldBackgroundColor: slate900,
    textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme).copyWith(
      displayLarge: GoogleFonts.outfit(fontWeight: FontWeight.bold, color: slate50),
      titleLarge: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: slate50),
      bodyLarge: GoogleFonts.outfit(color: slate50),
      bodyMedium: GoogleFonts.outfit(color: slate100),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: slate900,
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
    ),
    cardTheme: CardTheme(
      elevation: 0,
      color: slate800,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: slate700, width: 1),
      ),
      margin: const EdgeInsets.only(bottom: 12),
    ),
    dividerTheme: DividerThemeData(color: slate700, thickness: 1),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: sky400,
        foregroundColor: slate900,
        textStyle: GoogleFonts.outfit(fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}

