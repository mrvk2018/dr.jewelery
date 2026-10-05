import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/l10n/app_language.dart';
import '../../../../core/l10n/profile_localizations.dart';
import '../../../../core/utils/won_format.dart';
import '../../../../core/l10n/support_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../support/presentation/widgets/feedback_bottom_sheet.dart';
import '../../domain/models/order_item.dart';
import '../../domain/models/user_profile.dart';
import 'loyalty_qr_card.dart';
import 'profile_social_link_button.dart';

/// Экран профиля для авторизованного пользователя.
class ProfileAuthenticatedView extends StatelessWidget {
  const ProfileAuthenticatedView({
    super.key,
    required this.user,
    required this.orders,
    required this.onLogout,
    required this.onDeleteAccount,
    required this.onOpenAdminPanel,
    required this.onLanguageTap,
    required this.onSecretAdminTap,
    this.showAccountLinkBanner = false,
    this.isLinkingSocialAccount = false,
    this.onLinkGoogle,
    this.onLinkApple,
  });

  final UserProfile user;
  final List<OrderItem> orders;
  final VoidCallback onLogout;
  final Future<void> Function() onDeleteAccount;
  final VoidCallback onOpenAdminPanel;
  final VoidCallback onLanguageTap;
  final VoidCallback onSecretAdminTap;
  final bool showAccountLinkBanner;
  final bool isLinkingSocialAccount;
  final VoidCallback? onLinkGoogle;
  final VoidCallback? onLinkApple;

  bool get _showAppleLink {
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _ProfileHeader(user: user, onSecretAdminTap: onSecretAdminTap),
        const SizedBox(height: 16),
        _BonusBalanceCard(balance: user.bonusBalance),
        const SizedBox(height: 16),
        LoyaltyQrCard(
          cardNumber: user.loyaltyCardNumber,
          ownerName: user.name,
        ),
        if (showAccountLinkBanner) ...[
          const SizedBox(height: 16),
          _AccountLinkPremiumBanner(
            languageCode: context.langCode,
            isLinking: isLinkingSocialAccount,
            showApple: _showAppleLink,
            onLinkGoogle: onLinkGoogle,
            onLinkApple: onLinkApple,
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Мои заказы',
          style: AppTypography.heading(fontSize: 20),
        ),
        const SizedBox(height: 12),
        if (orders.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              'У вас пока нет заказов',
              style: AppTypography.productMeta().copyWith(fontSize: 14),
            ),
          )
        else
          ...orders.map(
            (order) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _OrderHistoryTile(order: order),
            ),
          ),
        ProfileLanguageTile(onTap: onLanguageTap),
        const SizedBox(height: 8),
        if (user.isAdmin) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: onOpenAdminPanel,
              icon: const Icon(Icons.admin_panel_settings_outlined),
              label: const Text('Панель управления'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: const BorderSide(color: AppColors.accent),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton.icon(
            onPressed: () => FeedbackBottomSheet.show(
              context,
              language: context.appLanguage,
            ),
            icon: const Icon(Icons.support_agent_outlined, size: 20),
            label: Text(
              supportTr(
                SupportStringKeys.feedbackButton,
                context.langCode,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: TextButton(
            onPressed: onLogout,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(user.isAdmin ? 'Выйти из админки' : 'Выйти'),
          ),
        ),
        if (!user.isAdmin) ...[
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: TextButton(
              onPressed: () => _confirmDeleteAccount(
                context,
                onDeleteAccount: onDeleteAccount,
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.saleRed,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                profileTr(
                  ProfileStringKeys.deleteAccountButton,
                  context.langCode,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 8),
        ProfileVersionLabel(onSecretTap: onSecretAdminTap),
      ],
    );
  }
}

Future<void> _confirmDeleteAccount(
  BuildContext context, {
  required Future<void> Function() onDeleteAccount,
}) async {
  final lang = context.langCode;
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      return AlertDialog(
        title: Text(
          profileTr(ProfileStringKeys.deleteAccountTitle, lang),
          style: AppTypography.heading(fontSize: 18),
        ),
        content: SingleChildScrollView(
          child: Text(
            profileTr(ProfileStringKeys.deleteAccountWarning, lang),
            style: AppTypography.productMeta().copyWith(height: 1.45),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              profileTr(ProfileStringKeys.deleteAccountCancel, lang),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.saleRed),
            child: Text(
              profileTr(ProfileStringKeys.deleteAccountConfirm, lang),
            ),
          ),
        ],
      );
    },
  );

  if (confirmed != true || !context.mounted) return;
  await onDeleteAccount();
}

class _AccountLinkPremiumBanner extends StatelessWidget {
  const _AccountLinkPremiumBanner({
    required this.languageCode,
    required this.isLinking,
    required this.showApple,
    this.onLinkGoogle,
    this.onLinkApple,
  });

  final String languageCode;
  final bool isLinking;
  final bool showApple;
  final VoidCallback? onLinkGoogle;
  final VoidCallback? onLinkApple;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.accent.withValues(alpha: 0.12),
            AppColors.cardBackground,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.verified_user_outlined,
                color: AppColors.accent,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  profileTr(ProfileStringKeys.linkAccountMessage, languageCode),
                  style: AppTypography.productMeta().copyWith(
                    fontSize: 14,
                    height: 1.45,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ProfileSocialLinkButton.google(
            label: profileTr(ProfileStringKeys.linkGoogle, languageCode),
            onPressed: onLinkGoogle,
            isLoading: isLinking,
          ),
          if (showApple) ...[
            const SizedBox(height: 12),
            ProfileSocialLinkButton.apple(
              label: profileTr(ProfileStringKeys.linkApple, languageCode),
              onPressed: onLinkApple,
              isLoading: isLinking,
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.user,
    required this.onSecretAdminTap,
  });

  final UserProfile user;
  final VoidCallback onSecretAdminTap;

  @override
  Widget build(BuildContext context) {
    final initials = user.name
        .split(' ')
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part[0])
        .join();

    return Row(
      children: [
        GestureDetector(
          key: const Key('profile_secret_avatar'),
          onTap: onSecretAdminTap,
          child: CircleAvatar(
            radius: 28,
            backgroundColor: AppColors.primary,
            child: Text(
              initials.toUpperCase(),
              style: AppTypography.caption(
                color: AppColors.accent,
                fontWeight: FontWeight.w700,
              ).copyWith(fontSize: 18),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(user.name, style: AppTypography.heading(fontSize: 22)),
              const SizedBox(height: 2),
              Text(
                user.email,
                style: AppTypography.productMeta().copyWith(fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BonusBalanceCard extends StatelessWidget {
  const _BonusBalanceCard({required this.balance});

  final int balance;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.bannerDark],
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.stars_rounded, color: AppColors.accent, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Бонусный баланс',
                  style: AppTypography.caption(
                    color: AppColors.textOnPrimary.withValues(alpha: 0.75),
                  ).copyWith(fontSize: 12),
                ),
                Text(
                  formatWon(balance),
                  style: AppTypography.heading(
                    fontSize: 22,
                    color: AppColors.textOnPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderHistoryTile extends StatelessWidget {
  const _OrderHistoryTile({required this.order});

  final OrderItem order;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  order.productName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.productName(),
                ),
              ),
              _StatusChip(label: order.status.label),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                order.dateLabel,
                style: AppTypography.productMeta(),
              ),
              Text(
                formatWon(order.amount),
                style: AppTypography.price(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppTypography.caption(
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
        ).copyWith(fontSize: 11),
      ),
    );
  }
}

class ProfileLanguageTile extends StatelessWidget {
  const ProfileLanguageTile({super.key, required this.onTap});

  final VoidCallback onTap;

  String _title(AppLanguage language) {
    return switch (language) {
      AppLanguage.ru => 'Язык приложения',
      AppLanguage.kk => 'Қосымша тілі',
      AppLanguage.ko => '앱 언어',
      AppLanguage.en => 'App language',
      AppLanguage.uz => 'Ilova tili',
    };
  }

  @override
  Widget build(BuildContext context) {
    final language = context.appLanguage;
    return Material(
      color: AppColors.cardBackground,
      borderRadius: BorderRadius.circular(12),
      child: ListTile(
        onTap: onTap,
        leading: const Icon(Icons.language_rounded, color: AppColors.accent),
        title: Text(_title(language), style: AppTypography.productName()),
        subtitle: Text(
          '${language.flagEmoji}  ${language.label}',
          style: AppTypography.productMeta(),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
    );
  }
}

class ProfileVersionLabel extends StatelessWidget {
  const ProfileVersionLabel({super.key, required this.onSecretTap});

  final VoidCallback onSecretTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSecretTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Dr. Jewelry  ·  v1.0.0',
          textAlign: TextAlign.center,
          style: AppTypography.caption(
            color: AppColors.textSecondary.withValues(alpha: 0.55),
          ).copyWith(fontSize: 11),
        ),
      ),
    );
  }
}
