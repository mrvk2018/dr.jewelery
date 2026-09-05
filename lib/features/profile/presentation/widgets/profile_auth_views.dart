import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/l10n/app_language.dart';
import '../../../../core/utils/won_format.dart';
import '../../../../core/l10n/support_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../support/presentation/widgets/feedback_bottom_sheet.dart';
import '../../../../shared/providers/locale_provider.dart';
import '../../domain/models/order_item.dart';
import '../../domain/models/user_profile.dart';
import 'loyalty_qr_card.dart';
import 'social_auth_button.dart';

/// Экран профиля для неавторизованного пользователя (гость).
class ProfileGuestView extends StatelessWidget {
  const ProfileGuestView({
    super.key,
    required this.onGoogleSignIn,
    required this.onAppleSignIn,
    required this.onLanguageTap,
    required this.onSecretAdminTap,
  });

  final VoidCallback onGoogleSignIn;
  final VoidCallback onAppleSignIn;
  final VoidCallback onLanguageTap;
  final VoidCallback onSecretAdminTap;

  bool get _showAppleSignIn {
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: AppColors.cardBackground,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.06),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            children: [
              GestureDetector(
                key: const Key('profile_secret_avatar'),
                onTap: onSecretAdminTap,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.background,
                    border: Border.all(color: AppColors.accent, width: 1.5),
                  ),
                  child: const Icon(
                    Icons.person_outline_rounded,
                    size: 36,
                    color: AppColors.accent,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Добро пожаловать',
                style: AppTypography.heading(fontSize: 24),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Войдите, чтобы копить бонусы и оформлять заказы',
                textAlign: TextAlign.center,
                style: AppTypography.productMeta().copyWith(fontSize: 14),
              ),
              const SizedBox(height: 24),
              SocialAuthButton.google(onPressed: onGoogleSignIn),
              if (_showAppleSignIn) ...[
                const SizedBox(height: 12),
                SocialAuthButton.apple(onPressed: onAppleSignIn),
              ],
              const SizedBox(height: 16),
              FeedbackButton(
                language: LocaleScope.of(context).language,
              ),
              const SizedBox(height: 8),
              ProfileLanguageTile(onTap: onLanguageTap),
              const SizedBox(height: 8),
              ProfileVersionLabel(onSecretTap: onSecretAdminTap),
            ],
          ),
        ),
      ),
    );
  }
}

/// Экран профиля для авторизованного пользователя.
class ProfileAuthenticatedView extends StatelessWidget {
  const ProfileAuthenticatedView({
    super.key,
    required this.user,
    required this.orders,
    required this.onLogout,
    required this.onOpenAdminPanel,
    required this.onLanguageTap,
    required this.onSecretAdminTap,
  });

  final UserProfile user;
  final List<OrderItem> orders;
  final VoidCallback onLogout;
  final VoidCallback onOpenAdminPanel;
  final VoidCallback onLanguageTap;
  final VoidCallback onSecretAdminTap;

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
              language: LocaleScope.of(context).language,
            ),
            icon: const Icon(Icons.support_agent_outlined, size: 20),
            label: Text(
              supportTr(
                SupportStringKeys.feedbackButton,
                LocaleScope.of(context).language,
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
        const SizedBox(height: 8),
        ProfileVersionLabel(onSecretTap: onSecretAdminTap),
      ],
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
                  '$balance бонусов',
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
    final language = LocaleScope.of(context).language;
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
