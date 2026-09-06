import 'app_locale_codes.dart';
import 'catalog_copy.dart';

export 'catalog_copy.dart';

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

  /// Целая строка атрибута каталога (металл, категория, вставка).
  static String attribute(String value, {required String languageCode}) {
    final map = catalogAttributeTranslations[value];
    if (map == null) return value;
    return resolve(map, languageCode: languageCode);
  }

  static String productDetail(String key, {required String languageCode}) {
    final map = productDetailCopy[key];
    if (map == null) return key;
    return resolve(map, languageCode: languageCode);
  }

  static bool containsQuery(Map<String, String> values, String query) {
    final normalized = query.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    return values.values.any((value) => value.toLowerCase().contains(normalized));
  }
}

/// Полные фразы каталога на 5 языках. Без пословного replace.
Map<String, String> demoLocalizedName(String ru) {
  final full = catalogNameTranslations[ru];
  if (full != null) return Map<String, String>.from(full);
  return {for (final code in AppLocaleCodes.all) code: ru};
}

Map<String, String> demoLocalizedDescription(String ru) {
  final full = catalogDescriptionTranslations[ru];
  if (full != null) return Map<String, String>.from(full);
  return {for (final code in AppLocaleCodes.all) code: ru};
}
