import 'package:flutter/material.dart';

import '../../core/l10n/app_language.dart';
import '../../core/services/onboarding_storage.dart';

/// Глобальный провайдер текущей локали приложения.
class LocaleProvider extends ChangeNotifier {
  LocaleProvider(this._storage) : _language = _storage.savedLanguage;

  final OnboardingStorage _storage;
  AppLanguage _language;

  AppLanguage get language => _language;
  Locale get locale => _language.locale;
  String get languageCode => _language.code;

  Future<void> setLanguage(AppLanguage language) async {
    if (_language == language) return;
    _language = language;
    await _storage.saveLanguage(language);
    notifyListeners();
  }

  Future<void> setLanguageCode(String code) async {
    await setLanguage(AppLanguage.fromCode(code));
  }
}

/// Доступ к [LocaleProvider] из дерева виджетов.
class LocaleScope extends InheritedNotifier<LocaleProvider> {
  const LocaleScope({
    super.key,
    required LocaleProvider provider,
    required super.child,
  }) : super(notifier: provider);

  static LocaleProvider of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<LocaleScope>();
    assert(scope != null, 'LocaleScope не найден в дереве виджетов');
    return scope!.notifier!;
  }
}
