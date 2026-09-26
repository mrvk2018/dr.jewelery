import 'package:shared_preferences/shared_preferences.dart';

/// Локальный кэш полей доставки на экране checkout.
abstract final class CheckoutAddressStorageKeys {
  static const postalCode = 'cached_postal_code';
  static const roadAddress = 'cached_road_address';
  static const detailAddress = 'cached_detail_address';
  static const recipientName = 'cached_recipient_name';
  static const phone = 'cached_phone';
}

class CheckoutAddressStorage {
  CheckoutAddressStorage(this._prefs);

  final SharedPreferences _prefs;

  static Future<CheckoutAddressStorage> create() async {
    final prefs = await SharedPreferences.getInstance();
    return CheckoutAddressStorage(prefs);
  }

  String get postalCode => _prefs.getString(CheckoutAddressStorageKeys.postalCode) ?? '';

  String get roadAddress => _prefs.getString(CheckoutAddressStorageKeys.roadAddress) ?? '';

  String get detailAddress =>
      _prefs.getString(CheckoutAddressStorageKeys.detailAddress) ?? '';

  String get recipientName =>
      _prefs.getString(CheckoutAddressStorageKeys.recipientName) ?? '';

  String get phone => _prefs.getString(CheckoutAddressStorageKeys.phone) ?? '';

  Future<void> save({
    required String postalCode,
    required String roadAddress,
    required String detailAddress,
    required String recipientName,
    required String phone,
  }) async {
    await _prefs.setString(CheckoutAddressStorageKeys.postalCode, postalCode);
    await _prefs.setString(CheckoutAddressStorageKeys.roadAddress, roadAddress);
    await _prefs.setString(
      CheckoutAddressStorageKeys.detailAddress,
      detailAddress,
    );
    await _prefs.setString(
      CheckoutAddressStorageKeys.recipientName,
      recipientName,
    );
    await _prefs.setString(CheckoutAddressStorageKeys.phone, phone);
  }
}
