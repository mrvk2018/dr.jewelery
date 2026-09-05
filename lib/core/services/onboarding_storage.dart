import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/app_language.dart';

/// Ключи локального хранилища приложения.
abstract final class AppStorageKeys {
  static const onboardingComplete = 'onboarding_complete';
  static const appLanguage = 'app_language';
}

/// Сервис сохранения состояния онбординга и языка.
class OnboardingStorage {
  OnboardingStorage(this._prefs);

  final SharedPreferences _prefs;

  static Future<OnboardingStorage> create() async {
    final prefs = await SharedPreferences.getInstance();
    return OnboardingStorage(prefs);
  }

  bool get isOnboardingComplete =>
      _prefs.getBool(AppStorageKeys.onboardingComplete) ?? false;

  AppLanguage get savedLanguage =>
      AppLanguage.fromCode(_prefs.getString(AppStorageKeys.appLanguage));

  Future<void> saveLanguage(AppLanguage language) async {
    await _prefs.setString(AppStorageKeys.appLanguage, language.code);
  }

  Future<void> completeOnboarding() async {
    await _prefs.setBool(AppStorageKeys.onboardingComplete, true);
  }

  Future<void> resetOnboarding() async {
    await _prefs.remove(AppStorageKeys.onboardingComplete);
  }
}
