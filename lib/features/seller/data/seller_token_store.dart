import 'package:shared_preferences/shared_preferences.dart';

/// Энергонезависимый код продавца (AEU-256 и т.п.).
class SellerTokenStore {
  SellerTokenStore(this._prefs);

  static const _key = 'dj_seller_staff_code_v1';

  final SharedPreferences _prefs;

  static Future<SellerTokenStore> create() async {
    final prefs = await SharedPreferences.getInstance();
    return SellerTokenStore(prefs);
  }

  String? get staffCode {
    final raw = _prefs.getString(_key)?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw.toUpperCase();
  }

  Future<void> saveStaffCode(String code) async {
    await _prefs.setString(_key, code.trim().toUpperCase());
  }

  Future<void> clear() async {
    await _prefs.remove(_key);
  }
}
