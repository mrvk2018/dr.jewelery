import 'package:shared_preferences/shared_preferences.dart';

/// Активная смена продавца в веб-панели (пасхалка / AdminWebShell).
class AdminStaffSession {
  const AdminStaffSession({
    required this.promoCode,
    required this.name,
  });

  final String promoCode;
  final String name;
}

/// SharedPreferences: active seller + last selected в диалоге входа.
abstract final class AdminStaffSessionStore {
  static const _activeCodeKey = 'dj_active_seller_code_v1';
  static const _activeNameKey = 'dj_active_seller_name_v1';
  static const _lastSelectedCodeKey = 'dj_last_selected_seller_code_v1';

  static Future<AdminStaffSession?> readActiveSession() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_activeCodeKey)?.trim().toUpperCase();
    final name = prefs.getString(_activeNameKey)?.trim();
    if (code == null || code.isEmpty || name == null || name.isEmpty) {
      return null;
    }
    return AdminStaffSession(promoCode: code, name: name);
  }

  static Future<void> saveActiveSession({
    required String promoCode,
    required String name,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final code = promoCode.trim().toUpperCase();
    await prefs.setString(_activeCodeKey, code);
    await prefs.setString(_activeNameKey, name.trim());
    await prefs.setString(_lastSelectedCodeKey, code);
  }

  static Future<void> clearActiveSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_activeCodeKey);
    await prefs.remove(_activeNameKey);
  }

  static Future<String?> readLastSelectedCode() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastSelectedCodeKey)?.trim().toUpperCase();
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  static Future<void> saveLastSelectedCode(String promoCode) async {
    final prefs = await SharedPreferences.getInstance();
    final code = promoCode.trim().toUpperCase();
    if (code.isEmpty) return;
    await prefs.setString(_lastSelectedCodeKey, code);
  }
}