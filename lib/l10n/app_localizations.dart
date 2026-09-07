import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_kk.dart';
import 'app_localizations_ko.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_uz.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('ru'),
    Locale('kk'),
    Locale('ko'),
    Locale('en'),
    Locale('uz'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In ru, this message translates to:
  /// **'Dr. Jewelry'**
  String get appTitle;

  /// No description provided for @appTagline.
  ///
  /// In ru, this message translates to:
  /// **'Вечная элегантность, созданная для вас'**
  String get appTagline;

  /// No description provided for @home.
  ///
  /// In ru, this message translates to:
  /// **'Главная'**
  String get home;

  /// No description provided for @catalog.
  ///
  /// In ru, this message translates to:
  /// **'Каталог'**
  String get catalog;

  /// No description provided for @cart.
  ///
  /// In ru, this message translates to:
  /// **'Корзина'**
  String get cart;

  /// No description provided for @favorites.
  ///
  /// In ru, this message translates to:
  /// **'Избранное'**
  String get favorites;

  /// No description provided for @favoritesEmptyTitle.
  ///
  /// In ru, this message translates to:
  /// **'Пока нет избранного'**
  String get favoritesEmptyTitle;

  /// No description provided for @favoritesEmptySubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Нажмите на сердце на карточке украшения — и оно появится здесь'**
  String get favoritesEmptySubtitle;

  /// No description provided for @profile.
  ///
  /// In ru, this message translates to:
  /// **'Профиль'**
  String get profile;

  /// No description provided for @support.
  ///
  /// In ru, this message translates to:
  /// **'Поддержка'**
  String get support;

  /// No description provided for @addToCart.
  ///
  /// In ru, this message translates to:
  /// **'В корзину'**
  String get addToCart;

  /// No description provided for @outOfStock.
  ///
  /// In ru, this message translates to:
  /// **'Нет в наличии'**
  String get outOfStock;

  /// No description provided for @continueOnboarding.
  ///
  /// In ru, this message translates to:
  /// **'Продолжить'**
  String get continueOnboarding;

  /// No description provided for @translateAllLanguages.
  ///
  /// In ru, this message translates to:
  /// **'Перевести на все языки (AI)'**
  String get translateAllLanguages;

  /// No description provided for @translating.
  ///
  /// In ru, this message translates to:
  /// **'Переводим...'**
  String get translating;

  /// No description provided for @translationDone.
  ///
  /// In ru, this message translates to:
  /// **'Переводы заполнены — проверьте и при необходимости отредактируйте'**
  String get translationDone;

  /// No description provided for @productNameRu.
  ///
  /// In ru, this message translates to:
  /// **'Название (RU)'**
  String get productNameRu;

  /// No description provided for @productDescriptionRu.
  ///
  /// In ru, this message translates to:
  /// **'Описание (RU)'**
  String get productDescriptionRu;

  /// No description provided for @translationsTitle.
  ///
  /// In ru, this message translates to:
  /// **'Переводы (KO / EN / UZ / KK)'**
  String get translationsTitle;

  /// No description provided for @languageKo.
  ///
  /// In ru, this message translates to:
  /// **'한국어 (KO)'**
  String get languageKo;

  /// No description provided for @languageEn.
  ///
  /// In ru, this message translates to:
  /// **'English (EN)'**
  String get languageEn;

  /// No description provided for @languageUz.
  ///
  /// In ru, this message translates to:
  /// **'O\'zbekcha (UZ)'**
  String get languageUz;

  /// No description provided for @languageKk.
  ///
  /// In ru, this message translates to:
  /// **'Қазақша (KK)'**
  String get languageKk;

  /// No description provided for @homeRecommendedTitle.
  ///
  /// In ru, this message translates to:
  /// **'Рекомендуем для вас'**
  String get homeRecommendedTitle;

  /// No description provided for @homePromoTitle.
  ///
  /// In ru, this message translates to:
  /// **'ГРАНДИОЗНАЯ\nРАСПРОДАЖА'**
  String get homePromoTitle;

  /// No description provided for @homePromoSubtitle.
  ///
  /// In ru, this message translates to:
  /// **'Эксклюзивные украшения по особым ценам'**
  String get homePromoSubtitle;

  /// No description provided for @homePromoBadge.
  ///
  /// In ru, this message translates to:
  /// **'LIMITED OFFER'**
  String get homePromoBadge;

  /// No description provided for @homePromoCountdownPrefix.
  ///
  /// In ru, this message translates to:
  /// **'До конца осталось'**
  String get homePromoCountdownPrefix;

  /// No description provided for @homeStoryDiscounts.
  ///
  /// In ru, this message translates to:
  /// **'Скидки\n-70%'**
  String get homeStoryDiscounts;

  /// No description provided for @homeStoryRings.
  ///
  /// In ru, this message translates to:
  /// **'Кольца'**
  String get homeStoryRings;

  /// No description provided for @homeStoryNew.
  ///
  /// In ru, this message translates to:
  /// **'Новинки'**
  String get homeStoryNew;

  /// No description provided for @homeStoryEarrings.
  ///
  /// In ru, this message translates to:
  /// **'Серьги'**
  String get homeStoryEarrings;

  /// No description provided for @homeStoryChains.
  ///
  /// In ru, this message translates to:
  /// **'Цепи'**
  String get homeStoryChains;

  /// No description provided for @homeStoryGifts.
  ///
  /// In ru, this message translates to:
  /// **'Подарки'**
  String get homeStoryGifts;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'kk', 'ko', 'ru', 'uz'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'kk':
      return AppLocalizationsKk();
    case 'ko':
      return AppLocalizationsKo();
    case 'ru':
      return AppLocalizationsRu();
    case 'uz':
      return AppLocalizationsUz();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
