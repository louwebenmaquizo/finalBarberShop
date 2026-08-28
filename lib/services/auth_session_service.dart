import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// AuthSessionService
/// Handles persistent user session across browser refreshes and app launches
class AuthSessionService {
  static const String _sessionKey = 'barber_user_session';

  /// Save logged in user session
  static Future<void> saveSession(Map<String, dynamic> userData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_sessionKey, jsonEncode(userData));
    } catch (e) {
      print('Error saving session: $e');
    }
  }

  /// Get active user session (returns null if not logged in)
  static Future<Map<String, dynamic>?> getSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final str = prefs.getString(_sessionKey);
      if (str != null && str.isNotEmpty) {
        final decoded = jsonDecode(str);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      }
    } catch (e) {
      print('Error reading session: $e');
    }
    return null;
  }

  /// Clear session on Logout
  static Future<void> clearSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_sessionKey);
    } catch (e) {
      print('Error clearing session: $e');
    }
  }
}
