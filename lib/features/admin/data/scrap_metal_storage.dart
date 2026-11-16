import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/store_location_utils.dart';

abstract final class ScrapMetalStorageKeys {
  static const storeLocation = 'scrap_metal_last_store';
  static const goldStandardRate = 'scrap_gold_standard_rate_krw';
  static const goldTradeinRate = 'scrap_gold_tradein_rate_krw';
  static const silverStandardRate = 'scrap_silver_standard_rate_krw';
  static const silverTradeinRate = 'scrap_silver_tradein_rate_krw';
}

class ScrapMetalStorage {
  ScrapMetalStorage(this._prefs);

  final SharedPreferences _prefs;

  static Future<ScrapMetalStorage> create() async {
    final prefs = await SharedPreferences.getInstance();
    return ScrapMetalStorage(prefs);
  }

  String get storeLocation {
    final raw = _prefs.getString(ScrapMetalStorageKeys.storeLocation);
    final upper = raw?.trim().toUpperCase() ?? '';
    if (upper == StoreLocationCode.ans) return StoreLocationCode.ans;
    return StoreLocationCode.icn;
  }

  Future<void> saveStoreLocation(String code) async {
    await _prefs.setString(
      ScrapMetalStorageKeys.storeLocation,
      code == StoreLocationCode.ans
          ? StoreLocationCode.ans
          : StoreLocationCode.icn,
    );
  }

  int get goldStandardRateKrw =>
      _prefs.getInt(ScrapMetalStorageKeys.goldStandardRate) ?? 0;

  int get goldTradeinRateKrw =>
      _prefs.getInt(ScrapMetalStorageKeys.goldTradeinRate) ?? 0;

  int get silverStandardRateKrw =>
      _prefs.getInt(ScrapMetalStorageKeys.silverStandardRate) ?? 0;

  int get silverTradeinRateKrw =>
      _prefs.getInt(ScrapMetalStorageKeys.silverTradeinRate) ?? 0;

  Future<void> saveGoldRates({required int standard, required int tradein}) async {
    await _prefs.setInt(ScrapMetalStorageKeys.goldStandardRate, standard);
    await _prefs.setInt(ScrapMetalStorageKeys.goldTradeinRate, tradein);
  }

  Future<void> saveSilverRates({required int standard, required int tradein}) async {
    await _prefs.setInt(ScrapMetalStorageKeys.silverStandardRate, standard);
    await _prefs.setInt(ScrapMetalStorageKeys.silverTradeinRate, tradein);
  }
}