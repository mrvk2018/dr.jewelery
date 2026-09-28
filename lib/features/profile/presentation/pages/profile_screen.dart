import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/supabase_config.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/l10n/app_language.dart';
import '../../../../core/l10n/profile_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/providers/cart_scope.dart';
import '../../../../shared/providers/locale_provider.dart';
import '../../../../shared/providers/profile_scope.dart';
import '../../../admin/presentation/pages/admin_panel_screen.dart';
import '../../../admin/presentation/widgets/admin_first_claim_dialog.dart';
import '../../../admin/presentation/widgets/admin_unlock_dialog.dart';
import '../widgets/profile_auth_views.dart';

/// Экран профиля покупателя (silent Supabase anonymous session).
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _adminTapWindow = Duration(seconds: 2);

  int _adminTapCount = 0;
  DateTime? _lastAdminTapAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshBonusFromCloud());
  }

  Future<void> _refreshBonusFromCloud() async {
    if (!mounted) return;
    final profile = ProfileScope.of(context);
    if (!profile.isAuthenticated || profile.user.isAdmin) return;
    await profile.refreshWalletFromCloud();
    if (!mounted) return;
    await CartScope.of(context).syncBonusBalanceFromProfile();
  }

  Future<void> _linkGoogleAccount() async {
    final profile = ProfileScope.of(context);
    final langCode = context.langCode;
    if (profile.isLinkingSocialAccount) return;
    try {
      await profile.linkGoogleAccount();
      if (!mounted) return;
      await CartScope.of(context).syncBonusBalanceFromProfile();
      _showAdminSnack(profileTr(ProfileStringKeys.linkSuccess, langCode));
    } catch (_) {
      if (!mounted) return;
      _showAdminSnack(profileTr(ProfileStringKeys.linkFailed, langCode));
    }
  }

  Future<void> _linkAppleAccount() async {
    final profile = ProfileScope.of(context);
    final langCode = context.langCode;
    if (profile.isLinkingSocialAccount) return;
    try {
      await profile.linkAppleAccount();
      if (!mounted) return;
      await CartScope.of(context).syncBonusBalanceFromProfile();
      _showAdminSnack(profileTr(ProfileStringKeys.linkSuccess, langCode));
    } catch (_) {
      if (!mounted) return;
      _showAdminSnack(profileTr(ProfileStringKeys.linkFailed, langCode));
    }
  }

  Future<void> _logout() async {
    _adminTapCount = 0;
    _lastAdminTapAt = null;
    await ProfileScope.of(context).logout();
    if (!mounted) return;
    await CartScope.of(context).syncBonusBalanceFromProfile();
  }

  /// Скрытый вход: 5 быстрых тапов по аватару / версии.
  Future<void> _onSecretAdminTap() async {
    final now = DateTime.now();
    if (_lastAdminTapAt == null ||
        now.difference(_lastAdminTapAt!) > _adminTapWindow) {
      _adminTapCount = 1;
    } else {
      _adminTapCount += 1;
    }
    _lastAdminTapAt = now;

    if (_adminTapCount < 5) return;
    _adminTapCount = 0;
    await _handleAdminEasterEgg();
  }

  Future<void> _handleAdminEasterEgg() async {
    final profile = ProfileScope.of(context);
    if (profile.user.isAdmin) {
      _showAdminSnack('Режим администратора Dr. Jewelry уже активен');
      return;
    }

    final claimed = await profile.isAdminDeviceClaimed();
    if (!mounted) return;

    if (!claimed) {
      await _runAdminFirstClaim();
      return;
    }

    final unlocked = await showAdminPinUnlockDialog(context);
    if (!mounted || !unlocked) return;
    _showAdminSnack('Режим администратора успешно активирован!');
  }

  Future<void> _runAdminFirstClaim() async {
    final creds = await showAdminFirstClaimDialog(context);
    if (creds == null || !mounted) return;

    // Отдельный клиент: signInWithPassword не затрагивает сессию Supabase.instance.
    final verifyClient = SupabaseClient(
      SupabaseConfig.projectUrl,
      SupabaseConfig.anonKey,
    );

    try {
      final response = await verifyClient.auth.signInWithPassword(
        email: creds.email.trim(),
        password: creds.password,
      );

      if (response.user == null) {
        if (!mounted) return;
        _showAdminSnack('Доступ запрещен: неверные данные администратора');
        return;
      }

      await verifyClient.auth.signOut();
      if (!mounted) return;

      await ProfileScope.of(context).completeAdminFirstClaim(creds.pin);
      if (!mounted) return;
      _showAdminSnack('Режим администратора успешно активирован!');
    } catch (_) {
      if (!mounted) return;
      _showAdminSnack('Доступ запрещен: неверные данные администратора');
    } finally {
      verifyClient.dispose();
    }
  }

  void _showAdminSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppTypography.caption(
            color: AppColors.textOnPrimary,
            fontWeight: FontWeight.w600,
          ).copyWith(fontSize: 14),
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _showLanguageDialog() async {
    final localeProvider = LocaleScope.of(context);
    final selected = await showDialog<AppLanguage>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            _languageDialogTitle(localeProvider.language),
            style: AppTypography.heading(fontSize: 20),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final language in AppLanguage.values)
                ListTile(
                  leading: Text(language.flagEmoji, style: const TextStyle(fontSize: 20)),
                  title: Text(language.label),
                  trailing: language == localeProvider.language
                      ? const Icon(Icons.check_rounded, color: AppColors.accent)
                      : null,
                  onTap: () => Navigator.of(dialogContext).pop(language),
                ),
            ],
          ),
        );
      },
    );

    if (selected == null || !mounted) return;
    await localeProvider.setLanguage(selected);
  }

  Future<void> _openAdminPanel() async {
    final profile = ProfileScope.of(context);
    if (!profile.user.isAdmin) return;

    final verified = await showAdminPinUnlockDialog(
      context,
      forPanelAccess: true,
    );
    if (!mounted || !verified) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const AdminPanelScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ProfileScope.of(context);

    return ListenableBuilder(
      listenable: profile,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Text(context.l10n.profile),
            centerTitle: false,
            titleTextStyle: AppTypography.heading(fontSize: 24),
          ),
          body: SafeArea(
            child: profile.isLoading
                ? const Center(child: CircularProgressIndicator())
                : ProfileAuthenticatedView(
                    user: profile.user,
                    orders: profile.orders,
                    onLogout: _logout,
                    onOpenAdminPanel: _openAdminPanel,
                    onLanguageTap: _showLanguageDialog,
                    onSecretAdminTap: _onSecretAdminTap,
                    showAccountLinkBanner:
                        profile.isAnonymousAccount && !profile.user.isAdmin,
                    isLinkingSocialAccount: profile.isLinkingSocialAccount,
                    onLinkGoogle: _linkGoogleAccount,
                    onLinkApple: _linkAppleAccount,
                  ),
          ),
        );
      },
    );
  }
}

String _languageDialogTitle(AppLanguage language) {
  return switch (language) {
    AppLanguage.ru => 'Язык приложения',
    AppLanguage.kk => 'Қосымша тілі',
    AppLanguage.ko => '앱 언어',
    AppLanguage.en => 'App language',
    AppLanguage.uz => 'Ilova tili',
  };
}
