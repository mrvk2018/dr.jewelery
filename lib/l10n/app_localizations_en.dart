// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Dr. Jewelry';

  @override
  String get catalog => 'Catalog';

  @override
  String get cart => 'Cart';

  @override
  String get profile => 'Profile';

  @override
  String get addToCart => 'Add to cart';

  @override
  String get translateAllLanguages => 'Translate to all languages (AI)';

  @override
  String get translating => 'Translating...';

  @override
  String get translationDone =>
      'Translations filled — review and edit if needed';

  @override
  String get productNameRu => 'Name (RU)';

  @override
  String get productDescriptionRu => 'Description (RU)';

  @override
  String get translationsTitle => 'Translations (KO / EN / UZ)';

  @override
  String get languageKo => '한국어 (KO)';

  @override
  String get languageEn => 'English (EN)';

  @override
  String get languageUz => 'O\'zbekcha (UZ)';
}
