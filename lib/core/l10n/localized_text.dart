import 'app_locale_codes.dart';

/// Утилиты для работы с Map локализованных текстов.
abstract final class LocalizedText {
  static String resolve(
    Map<String, String> values, {
    required String languageCode,
    String fallback = AppLocaleCodes.ru,
  }) {
    if (values.isEmpty) return '';
    return values[languageCode] ??
        values[fallback] ??
        values.values.firstWhere((value) => value.isNotEmpty, orElse: () => '');
  }

  static Map<String, String> single(String languageCode, String text) {
    return {languageCode: text};
  }

  static Map<String, String> fromRussianBase({
    required String ruName,
    required String ruDescription,
    Map<String, String>? nameOverrides,
    Map<String, String>? descriptionOverrides,
  }) {
    final names = Map<String, String>.from(demoLocalizedName(ruName));
    final descriptions =
        Map<String, String>.from(demoLocalizedDescription(ruDescription));
    if (nameOverrides != null) names.addAll(nameOverrides);
    if (descriptionOverrides != null) descriptions.addAll(descriptionOverrides);
    return names;
  }

  static bool containsQuery(Map<String, String> values, String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return values.values.any((value) => value.toLowerCase().contains(normalized));
  }
}

/// Демо-переводы для каталога (до подключения реального AI).
Map<String, String> demoLocalizedName(String ru) {
  return {
    AppLocaleCodes.ru: ru,
    AppLocaleCodes.ko: _demoKoName(ru),
    AppLocaleCodes.en: _demoEnName(ru),
    AppLocaleCodes.uz: _demoUzName(ru),
  };
}

Map<String, String> demoLocalizedDescription(String ru) {
  return {
    AppLocaleCodes.ru: ru,
    AppLocaleCodes.ko: '프리미엄 주얼리 컬렉션: $ru',
    AppLocaleCodes.en: 'Premium jewelry piece: $ru',
    AppLocaleCodes.uz: 'Premium zargarlik buyumi: $ru',
  };
}

String _demoKoName(String ru) {
  if (ru.contains('Кольцо')) return ru.replaceAll('Кольцо', '반지');
  if (ru.contains('Серьги')) return ru.replaceAll('Серьги', '귀걸이');
  if (ru.contains('Подвеска')) return ru.replaceAll('Подвеска', '펜던트');
  if (ru.contains('Браслет')) return ru.replaceAll('Браслет', '팔찌');
  if (ru.contains('Часы')) return ru.replaceAll('Часы', '시계');
  return '[$ru]';
}

String _demoEnName(String ru) {
  return switch (ru) {
    'Кольцо из белого золота с бриллиантом' =>
      'White gold diamond ring',
    'Серьги с изумрудом' => 'Emerald earrings',
    'Подвеска «Капля» с сапфиром' => 'Sapphire teardrop pendant',
    'Браслет с фианитами' => 'Phianite bracelet',
    'Подвеска «Сердце»' => 'Heart pendant',
    'Обручальное кольцо классическое' => 'Classic wedding band',
    'Часы «Sunlight Classic»' => 'Sunlight Classic watch',
    'Кольцо с топазом' => 'Topaz ring',
    _ => ru,
  };
}

String _demoUzName(String ru) {
  if (ru.contains('Кольцо')) return ru.replaceAll('Кольцо', 'Uzuk');
  if (ru.contains('Серьги')) return ru.replaceAll('Серьги', 'Sirg\'a');
  if (ru.contains('Подвеска')) return ru.replaceAll('Подвеска', 'Osma');
  if (ru.contains('Браслет')) return ru.replaceAll('Браслет', 'Bilaguzuk');
  if (ru.contains('Часы')) return ru.replaceAll('Часы', 'Soat');
  return ru;
}
