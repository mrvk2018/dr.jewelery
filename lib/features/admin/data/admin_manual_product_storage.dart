import 'package:shared_preferences/shared_preferences.dart';

/// Последний выбор «Золото» / «Серебро» в модалке ручного добавления товара.
abstract final class AdminManualProductStorageKeys {
  static const lastSelectedMetal = 'admin_last_selected_metal';
}

abstract final class AdminManualProductMetalCategory {
  static const gold = 'gold';
  static const silver = 'silver';

  static const allowed = {gold, silver};

  static String? normalizeStored(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    return allowed.contains(value) ? value : null;
  }
}

class AdminManualProductStorage {
  AdminManualProductStorage(this._prefs);

  final SharedPreferences _prefs;

  static Future<AdminManualProductStorage> create() async {
    final prefs = await SharedPreferences.getInstance();
    return AdminManualProductStorage(prefs);
  }

  String? get lastSelectedMetalCategory => AdminManualProductMetalCategory
      .normalizeStored(_prefs.getString(AdminManualProductStorageKeys.lastSelectedMetal));

  Future<void> saveLastSelectedMetalCategory(String category) async {
    final normalized = AdminManualProductMetalCategory.normalizeStored(category);
    if (normalized == null) return;
    await _prefs.setString(
      AdminManualProductStorageKeys.lastSelectedMetal,
      normalized,
    );
  }
}