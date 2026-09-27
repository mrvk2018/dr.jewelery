import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Ключи SharedPreferences для First Claim и интеграций.
abstract final class DeviceSecretKeys {
  static const adminPinHash = 'dj_admin_pin_hash';
  static const adminDeviceClaimed = 'dj_admin_device_claimed';
  static const posApiKey = 'dj_pos_api_key';
  static const tossApiKey = 'dj_toss_api_key';
}

/// Ключи POS и Toss Payments, хранящиеся только на устройстве.
class IntegrationKeys {
  const IntegrationKeys({
    this.posApiKey = '',
    this.tossApiKey = '',
  });

  final String posApiKey;
  final String tossApiKey;
}

/// Локальные секреты устройства: First Claim админки и API-ключи.
///
/// Не синхронизируются в облако — только SharedPreferences этого телефона.
class DeviceSecretsStore {
  DeviceSecretsStore(this._prefs);

  final SharedPreferences _prefs;

  bool get isAdminDeviceClaimed {
    final claimed = _prefs.getBool(DeviceSecretKeys.adminDeviceClaimed) ?? false;
    if (!claimed) return false;
    final pinHash = _prefs.getString(DeviceSecretKeys.adminPinHash);
    return pinHash != null && pinHash.isNotEmpty;
  }

  static bool isValidAdminPin(String pin) => RegExp(r'^\d{4}$').hasMatch(pin);

  Future<void> claimAdminDevicePin(String pin) async {
    if (!isValidAdminPin(pin)) {
      throw ArgumentError('PIN должен состоять из 4 цифр');
    }
    if (isAdminDeviceClaimed) {
      throw StateError('Владелец на этом устройстве уже назначен');
    }

    await _prefs.setString(
      DeviceSecretKeys.adminPinHash,
      hashAdminPassword(pin),
    );
    await _prefs.setBool(DeviceSecretKeys.adminDeviceClaimed, true);
  }

  bool verifyAdminPin(String pin) {
    if (!isAdminDeviceClaimed) return false;
    if (!isValidAdminPin(pin)) return false;
    final stored = _prefs.getString(DeviceSecretKeys.adminPinHash);
    if (stored == null || stored.isEmpty) return false;
    return verifyAdminPasswordHash(pin, stored);
  }

  IntegrationKeys loadIntegrationKeys() {
    return IntegrationKeys(
      posApiKey: _prefs.getString(DeviceSecretKeys.posApiKey) ?? '',
      tossApiKey: _prefs.getString(DeviceSecretKeys.tossApiKey) ?? '',
    );
  }

  Future<void> saveIntegrationKeys(IntegrationKeys keys) async {
    await _prefs.setString(DeviceSecretKeys.posApiKey, keys.posApiKey.trim());
    await _prefs.setString(
      DeviceSecretKeys.tossApiKey,
      keys.tossApiKey.trim(),
    );
  }

  /// SHA-256 + случайная соль. Формат: `sha256$<salt>$<hex>`.
  static String hashAdminPassword(String password) {
    final saltBytes = List<int>.generate(
      16,
      (_) => Random.secure().nextInt(256),
    );
    final salt = base64UrlEncode(saltBytes);
    final digest = sha256.convert(utf8.encode('$salt\n$password'));
    return 'sha256\$$salt\$${digest.toString()}';
  }

  static bool verifyAdminPasswordHash(String password, String stored) {
    final parts = stored.split('\$');
    if (parts.length != 3 || parts[0] != 'sha256') return false;
    final salt = parts[1];
    final expected = parts[2];
    final actual = sha256.convert(utf8.encode('$salt\n$password')).toString();
    return _constantTimeEquals(actual, expected);
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
