import 'package:flutter/widgets.dart';

import '../../l10n/app_localizations.dart';
import '../l10n/app_language.dart';

extension AppLocalizationsX on BuildContext {
  /// Быстрый доступ к сгенерированным ARB-переводам: `context.l10n.profile`.
  AppLocalizations get l10n => AppLocalizations.of(this);

  /// Текущий код языка (`ru`, `kk`, `ko`, `en`, `uz`): `context.langCode`.
  String get langCode => Localizations.localeOf(this).languageCode;

  /// Текущий [AppLanguage] из локали `MaterialApp` (без подписки на LocaleScope).
  AppLanguage get appLanguage => AppLanguage.fromCode(langCode);
}
