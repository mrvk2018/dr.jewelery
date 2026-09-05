import '../l10n/app_locale_codes.dart';
import '../l10n/localized_text.dart';

/// Результат AI-перевода названия и описания товара.
class AiTranslationResult {
  const AiTranslationResult({
    required this.names,
    required this.descriptions,
  });

  final Map<String, String> names;
  final Map<String, String> descriptions;
}

/// Заглушка онлайн-переводчика для админ-панели.
///
/// В будущем здесь будет вызов реального AI/API перевода.
Future<AiTranslationResult> translateProductFromRussian({
  required String ruName,
  required String ruDescription,
}) async {
  await Future<void>.delayed(const Duration(seconds: 1));

  final names = demoLocalizedName(ruName);
  final descriptions = demoLocalizedDescription(
    ruDescription.isEmpty
        ? 'Изысканное украшение из коллекции Sunlight.'
        : ruDescription,
  );

  return AiTranslationResult(
    names: {
      for (final code in AppLocaleCodes.translationTargets) code: names[code]!,
    },
    descriptions: {
      for (final code in AppLocaleCodes.translationTargets)
        code: descriptions[code]!,
    },
  );
}
