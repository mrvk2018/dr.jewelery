import 'package:flutter/material.dart';

import '../../../../core/l10n/app_language.dart';
import '../../../../core/services/admin_auth_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../shared/providers/locale_provider.dart';
import '../../../../shared/providers/profile_scope.dart';
import '../../../admin/presentation/pages/admin_owner_init_page.dart';
import '../../../admin/presentation/pages/admin_panel_screen.dart';
import '../../../admin/presentation/widgets/admin_unlock_dialog.dart';
import '../widgets/profile_auth_views.dart';

/// Экран профиля с гостевым и авторизованным режимами.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  static const _adminTapWindow = Duration(seconds: 2);

  int _adminTapCount = 0;
  DateTime? _lastAdminTapAt;

  void _signInWithGoogle() {
    ProfileScope.of(context).signInCustomer();
  }

  void _signInWithApple() {
    ProfileScope.of(context).signInCustomer();
  }

  void _logout() {
    _adminTapCount = 0;
    _lastAdminTapAt = null;
    ProfileScope.of(context).logout();
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
      final password = await Navigator.of(context).push<String>(
        MaterialPageRoute<String>(
          fullscreenDialog: true,
          builder: (_) => const AdminOwnerInitPage(),
        ),
      );
      if (password == null || !mounted) return;
      await profile.claimAdminAndSignIn(password);
      if (!mounted) return;
      _showAdminSnack('Режим администратора Dr. Jewelry активирован');
      return;
    }

    final unlocked = await showAdminUnlockDialog(context);
    if (!mounted || !unlocked) return;
    _showAdminSnack('Режим администратора Dr. Jewelry активирован');
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Запрос биометрии...',
          style: AppTypography.caption(
            color: AppColors.textOnPrimary,
            fontWeight: FontWeight.w600,
          ).copyWith(fontSize: 14),
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );

    final isVerified = await authenticateAdmin();
    if (!mounted || !isVerified) return;

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
            title: Text(AppLocalizations.of(context).profile),
            centerTitle: false,
            titleTextStyle: AppTypography.heading(fontSize: 24),
          ),
          body: SafeArea(
            child: profile.isAuthenticated
                ? ProfileAuthenticatedView(
                    user: profile.user,
                    orders: profile.orders,
                    onLogout: _logout,
                    onOpenAdminPanel: _openAdminPanel,
                    onLanguageTap: _showLanguageDialog,
                    onSecretAdminTap: _onSecretAdminTap,
                  )
                : ProfileGuestView(
                    onGoogleSignIn: _signInWithGoogle,
                    onAppleSignIn: _signInWithApple,
                    onLanguageTap: _showLanguageDialog,
                    onSecretAdminTap: _onSecretAdminTap,
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
