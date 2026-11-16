import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/store_location_utils.dart';

/// Последний выбор «Золото» / «Серебро» в модалке ручного добавления товара.
abstract final class AdminManualProductStorageKeys {
  static const lastSelectedMetal = 'admin_last_selected_metal';
  static const lastSelectedStoreLocation = 'admin_last_selected_store_location';
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

  String get lastSelectedStoreLocation => storeLocationPickerCodeFromPrefs(
        _prefs.getString(AdminManualProductStorageKeys.lastSelectedStoreLocation),
      );

  Future<void> saveLastSelectedStoreLocation(String code) async {
    if (code == StoreLocationCode.unselected) {
      await _prefs.setString(
        AdminManualProductStorageKeys.lastSelectedStoreLocation,
        '',
      );
      return;
    }
    await _prefs.setString(
      AdminManualProductStorageKeys.lastSelectedStoreLocation,
      normalizeStoreLocationCode(storeLocation: code),
    );
  }
}