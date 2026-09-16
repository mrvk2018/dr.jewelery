import 'package:translator/translator.dart';

import '../l10n/app_locale_codes.dart';

/// Результат AI-перевода названия и описания товара.
class AiTranslationResult {
  const AiTranslationResult({
    required this.names,
    required this.descriptions,
  });

  final Map<String, String> names;
  final Map<String, String> descriptions;
}

final GoogleTranslator _googleTranslator = GoogleTranslator();

/// Переводит название и описание с русского на kk, ko, en, uz через Google Translate.
Future<AiTranslationResult> translateProductFromRussian({
  required String ruName,
  required String ruDescription,
}) async {
  final descriptionSource = ruDescription.isEmpty
      ? 'Изысканное украшение из коллекции Dr. Jewelry.'
      : ruDescription;

  final names = <String, String>{};
  final descriptions = <String, String>{};

  await Future.wait(
    AppLocaleCodes.translationTargets.map((code) async {
      names[code] = await _translateFromRussian(ruName, code);
      descriptions[code] =
          await _translateFromRussian(descriptionSource, code);
    }),
  );

  return AiTranslationResult(names: names, descriptions: descriptions);
}

Future<String> _translateFromRussian(String text, String targetLanguageCode) async {
  if (text.trim().isEmpty) return '';

  final result = await _googleTranslator.translate(
    text,
    from: AppLocaleCodes.ru,
    to: targetLanguageCode,
  );
  return result.text;
}
