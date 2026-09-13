import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service responsible for managing, persisting, and notifying app-wide ThemeMode.
class ThemeService {
  static const String _prefKey = 'app_theme_mode';

  static final ValueNotifier<ThemeMode> themeModeNotifier =
      ValueNotifier<ThemeMode>(ThemeMode.light);

  /// Initializes ThemeService from SharedPreferences on app launch.
  static Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey) ?? 'light';
      if (saved == 'dark') {
        themeModeNotifier.value = ThemeMode.dark;
      } else if (saved == 'system') {
        themeModeNotifier.value = ThemeMode.system;
      } else {
        themeModeNotifier.value = ThemeMode.light;
      }
    } catch (_) {
      themeModeNotifier.value = ThemeMode.light;
    }
  }

  /// Sets the new ThemeMode and persists to SharedPreferences.
  static Future<void> setThemeMode(ThemeMode mode) async {
    themeModeNotifier.value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      final val = mode == ThemeMode.dark
          ? 'dark'
          : (mode == ThemeMode.system ? 'system' : 'light');
      await prefs.setString(_prefKey, val);
    } catch (_) {}
  }

  /// Current active ThemeMode.
  static ThemeMode get currentMode => themeModeNotifier.value;

  /// Returns true if currently in dark mode (taking system brightness into account if in system mode).
  static bool isDark(BuildContext context) {
    if (themeModeNotifier.value == ThemeMode.dark) return true;
    if (themeModeNotifier.value == ThemeMode.light) return false;
    return MediaQuery.of(context).platformBrightness == Brightness.dark;
  }
}

/// Centralized themes for Liem Barber Shop.
class AppTheme {
  static const Color primaryBlue = Color(0xFF5BBCFF);
  static const Color darkBackground = Color(0xFF121212);
  static const Color darkSurface = Color(0xFF1E1E1E);
  static const Color darkCard = Color(0xFF1E1E1E);
  static const Color darkBorder = Color(0xFF2C2C2C);

  /// Light Theme Definition
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        brightness: Brightness.light,
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: Colors.white,
      cardColor: Colors.white,
      dividerColor: Colors.grey[200],
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
      ),
      textTheme: GoogleFonts.manropeTextTheme(ThemeData.light().textTheme),
    );
  }

  /// Dark Theme Definition
  static ThemeData get darkTheme {
    final baseDark = ThemeData.dark(useMaterial3: true);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        brightness: Brightness.dark,
        surface: darkSurface,
      ),
      scaffoldBackgroundColor: darkBackground,
      cardColor: darkCard,
      dialogTheme: const DialogTheme(backgroundColor: Color(0xFF242424)),
      dividerColor: darkBorder,
      appBarTheme: const AppBarTheme(
        backgroundColor: darkSurface,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      textTheme: GoogleFonts.manropeTextTheme(baseDark.textTheme).apply(
        bodyColor: Colors.white,
        displayColor: Colors.white,
      ),
    );
  }
}

/// Convenience accessors for theme-adaptive colors.
class AppColors {
  static bool isDark(BuildContext context) => ThemeService.isDark(context);

  static Color background(BuildContext context) =>
      isDark(context) ? AppTheme.darkBackground : Colors.white;

  static Color surface(BuildContext context) =>
      isDark(context) ? AppTheme.darkSurface : Colors.white;

  static Color card(BuildContext context) =>
      isDark(context) ? AppTheme.darkCard : Colors.white;

  static Color cardBorder(BuildContext context) =>
      isDark(context) ? AppTheme.darkBorder : Colors.grey[200]!;

  static Color textPrimary(BuildContext context) =>
      isDark(context) ? Colors.white : Colors.black87;

  static Color textSecondary(BuildContext context) =>
      isDark(context) ? Colors.grey[400]! : Colors.grey[600]!;

  static Color inputBackground(BuildContext context) =>
      isDark(context) ? const Color(0xFF1E1E1E) : Colors.grey[50]!;

  static Color inputBorder(BuildContext context) =>
      isDark(context) ? AppTheme.darkBorder : Colors.grey[300]!;

  static Color divider(BuildContext context) =>
      isDark(context) ? AppTheme.darkBorder : Colors.grey[200]!;
}
