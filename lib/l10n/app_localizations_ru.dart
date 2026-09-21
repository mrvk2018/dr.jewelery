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
  String get appTagline => 'Вечная элегантность, созданная для вас';

  @override
  String get home => 'Главная';

  @override
  String get catalog => 'Каталог';

  @override
  String get cart => 'Корзина';

  @override
  String get favorites => 'Избранное';

  @override
  String get favoritesEmptyTitle => 'Пока нет избранного';

  @override
  String get favoritesEmptySubtitle =>
      'Нажмите на сердце на карточке украшения — и оно появится здесь';

  @override
  String get profile => 'Профиль';

  @override
  String get support => 'Поддержка';

  @override
  String get addToCart => 'В корзину';

  @override
  String get outOfStock => 'Нет в наличии';

  @override
  String get continueOnboarding => 'Продолжить';

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
  String get translationsTitle => 'Переводы (KO / EN / UZ / KK)';

  @override
  String get languageKo => '한국어 (KO)';

  @override
  String get languageEn => 'English (EN)';

  @override
  String get languageUz => 'O\'zbekcha (UZ)';

  @override
  String get languageKk => 'Қазақша (KK)';

  @override
  String get homeRecommendedTitle => 'Рекомендуем для вас';

  @override
  String get homePromoTitle => 'ГРАНДИОЗНАЯ\nРАСПРОДАЖА';

  @override
  String get homePromoSubtitle => 'Эксклюзивные украшения по особым ценам';

  @override
  String get homePromoBadge => 'LIMITED OFFER';

  @override
  String get homePromoCountdownPrefix => 'До конца осталось';

  @override
  String get homeStoryDiscounts => 'Скидки\n-70%';

  @override
  String get homeStoryRings => 'Кольца';

  @override
  String get homeStoryNew => 'Новинки';

  @override
  String get homeStoryEarrings => 'Серьги';

  @override
  String get homeStoryChains => 'Цепи';

  @override
  String get homeStoryGifts => 'Подарки';

  @override
  String get buyNow => 'Купить';

  @override
  String get filterAll => 'Все';

  @override
  String get filterGold => 'Золото';

  @override
  String get filterSilver => 'Серебро';

  @override
  String get productAddedToCart => 'Товар добавлен в корзину';

  @override
  String productWeightGrams(String weight) {
    return '$weight г';
  }

  @override
  String get homeCollectionsComingSoon => 'Скоро появятся новые коллекции';

  @override
  String get exitAppDialogTitle => 'Выйти из приложения?';

  @override
  String get exitAppDialogMessage => 'Вы действительно хотите выйти?';

  @override
  String get exitAppConfirm => 'Да';

  @override
  String get exitAppCancel => 'Нет';

  @override
  String get cartBonusLimitHint =>
      'Бонусами можно оплатить до 15% от стоимости товаров заказа';

  @override
  String get cartBonusDiscountLabel => 'Скидка за бонусы';
}
