// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get appTitle => 'Dr. Jewelry';

  @override
  String get catalog => 'Каталог';

  @override
  String get cart => 'Корзина';

  @override
  String get profile => 'Профиль';

  @override
  String get addToCart => 'В корзину';

  @override
  String get translateAllLanguages => 'Перевести на все языки (AI)';

  @override
  String get translating => 'Переводим...';

  @override
  String get translationDone =>
      'Переводы заполнены — проверьте и при необходимости отредактируйте';

  @override
  String get productNameRu => 'Название (RU)';

  @override
  String get productDescriptionRu => 'Описание (RU)';

  @override
  String get translationsTitle => 'Переводы (KO / EN / UZ)';

  @override
  String get languageKo => '한국어 (KO)';

  @override
  String get languageEn => 'English (EN)';

  @override
  String get languageUz => 'O\'zbekcha (UZ)';
}
