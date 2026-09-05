import 'package:flutter/material.dart';

/// Поддерживаемые языки приложения (ISO-коды локалей Flutter).
enum AppLanguage {
  ru('ru', 'Русский', 'RU', '🇷🇺'),
  ko('ko', '한국어', 'KO', '🇰🇷'),
  en('en', 'English', 'EN', '🇬🇧'),
  uz('uz', 'O\'zbekcha', 'UZ', '🇺🇿');

  const AppLanguage(this.code, this.label, this.shortCode, this.flagEmoji);

  final String code;
  final String label;
  final String shortCode;
  final String flagEmoji;

  Locale get locale => Locale(code);

  static List<Locale> get supportedLocales =>
      values.map((lang) => lang.locale).toList();

  static AppLanguage fromCode(String? code) {
    final normalized = switch (code) {
      'kr' => 'ko',
      null || '' => 'ru',
      _ => code,
    };
    return AppLanguage.values.firstWhere(
      (lang) => lang.code == normalized,
      orElse: () => AppLanguage.ru,
    );
  }

  static AppLanguage fromLocale(Locale locale) => fromCode(locale.languageCode);
}
