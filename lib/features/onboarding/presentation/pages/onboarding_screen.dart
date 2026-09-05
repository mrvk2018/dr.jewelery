import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/l10n/onboarding_localizations.dart';
import '../../../../core/services/onboarding_storage.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../profile/presentation/widgets/social_auth_button.dart';
import '../../../support/presentation/widgets/feedback_bottom_sheet.dart';
import '../../../../shared/providers/locale_provider.dart';

/// Премиальный онбординг: язык → PIPA compliance → авторизация.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.storage,
    required this.onComplete,
  });

  final OnboardingStorage storage;
  final Future<void> Function() onComplete;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0;
  bool _agreed = false;
  final ScrollController _complianceScrollController = ScrollController();

  @override
  void dispose() {
    _complianceScrollController.dispose();
    super.dispose();
  }

  AppLanguage get _language => LocaleScope.of(context).language;

  String tr(String key) => onboardingTr(key, _language);

  Future<void> _selectLanguage(AppLanguage language) async {
    await LocaleScope.of(context).setLanguage(language);
    if (!mounted) return;
    setState(() => _step = 1);
  }

  void _goToStep(int step) => setState(() => _step = step);

  Future<void> _finishOnboarding() async {
    await widget.onComplete();
  }

  bool get _showAppleSignIn {
    return defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StepIndicator(
                currentStep: _step,
                labels: [
                  tr(OnboardingStringKeys.stepLanguage),
                  tr(OnboardingStringKeys.stepCompliance),
                  tr(OnboardingStringKeys.stepAuth),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: switch (_step) {
                    0 => _LanguageStep(
                        key: const ValueKey('lang'),
                        language: _language,
                        title: tr(OnboardingStringKeys.chooseLanguageTitle),
                        onLanguageSelected: _selectLanguage,
                      ),
                    1 => _ComplianceStep(
                        key: const ValueKey('compliance'),
                        tr: tr,
                        agreed: _agreed,
                        scrollController: _complianceScrollController,
                        onAgreedChanged: (value) {
                          setState(() => _agreed = value);
                        },
                        onContinue: _agreed ? () => _goToStep(2) : null,
                      ),
                    _ => _AuthStep(
                        key: const ValueKey('auth'),
                        tr: tr,
                        language: _language,
                        showApple: _showAppleSignIn,
                        onGoogle: _finishOnboarding,
                        onApple: _finishOnboarding,
                        onSkip: _finishOnboarding,
                      ),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({
    required this.currentStep,
    required this.labels,
  });

  final int currentStep;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(labels.length, (index) {
        final isActive = index == currentStep;
        final isDone = index < currentStep;

        return Expanded(
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      height: 3,
                      decoration: BoxDecoration(
                        color: isDone || isActive
                            ? AppColors.accent
                            : AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  if (index < labels.length - 1) const SizedBox(width: 4),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                labels[index],
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption(
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive ? AppColors.primary : AppColors.textSecondary,
                ).copyWith(fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _LanguageStep extends StatelessWidget {
  const _LanguageStep({
    super.key,
    required this.language,
    required this.title,
    required this.onLanguageSelected,
  });

  final AppLanguage language;
  final String title;
  final ValueChanged<AppLanguage> onLanguageSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                Text(
                  title,
                  style: AppTypography.heading(fontSize: 26),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  'Dr. Jewelry',
                  textAlign: TextAlign.center,
                  style: AppTypography.caption(color: AppColors.textSecondary)
                      .copyWith(fontSize: 13, letterSpacing: 2),
                ),
                const SizedBox(height: 40),
                GridView.count(
                  shrinkWrap: true,
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.55,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (final lang in AppLanguage.values)
                      _LanguageTile(
                        language: lang,
                        isSelected: language == lang,
                        onTap: () => onLanguageSelected(lang),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.language,
    required this.isSelected,
    required this.onTap,
  });

  final AppLanguage language;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected ? AppColors.primary : AppColors.cardBackground,
      borderRadius: BorderRadius.circular(12),
      elevation: isSelected ? 2 : 0,
      shadowColor: AppColors.primary.withValues(alpha: 0.15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.border,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                language.flagEmoji,
                style: const TextStyle(fontSize: 32),
              ),
              const SizedBox(height: 10),
              Text(
                language.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption(
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? AppColors.textOnPrimary
                      : AppColors.textPrimary,
                ).copyWith(fontSize: 16),
              ),
              Text(
                language.shortCode,
                style: AppTypography.caption(
                  color: isSelected
                      ? AppColors.accent
                      : AppColors.textSecondary,
                ).copyWith(fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ComplianceStep extends StatelessWidget {
  const _ComplianceStep({
    super.key,
    required this.tr,
    required this.agreed,
    required this.scrollController,
    required this.onAgreedChanged,
    required this.onContinue,
  });

  final String Function(String key) tr;
  final bool agreed;
  final ScrollController scrollController;
  final ValueChanged<bool> onAgreedChanged;
  final VoidCallback? onContinue;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr(OnboardingStringKeys.complianceTitle),
          style: AppTypography.heading(fontSize: 22),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            tr(OnboardingStringKeys.pipaNotice),
            style: AppTypography.caption(
              color: AppColors.primary,
              fontWeight: FontWeight.w600,
            ).copyWith(fontSize: 11),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Scrollbar(
            controller: scrollController,
            thumbVisibility: true,
            radius: const Radius.circular(4),
            child: SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _LegalSection(
                    title: tr(OnboardingStringKeys.eulaTitle),
                    body: tr(OnboardingStringKeys.eulaBody),
                    viewLabel: tr(OnboardingStringKeys.viewDocument),
                  ),
                  const SizedBox(height: 12),
                  _LegalSection(
                    title: tr(OnboardingStringKeys.privacyTitle),
                    body: tr(OnboardingStringKeys.privacyBody),
                    viewLabel: tr(OnboardingStringKeys.viewDocument),
                  ),
                  const SizedBox(height: 12),
                  _PermissionsSection(
                    title: tr(OnboardingStringKeys.permissionsTitle),
                    items: [
                      (
                        Icons.smartphone_outlined,
                        tr(OnboardingStringKeys.permissionDeviceId),
                      ),
                      (
                        Icons.notifications_active_outlined,
                        tr(OnboardingStringKeys.permissionNotifications),
                      ),
                      (
                        Icons.camera_alt_outlined,
                        tr(OnboardingStringKeys.permissionCamera),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _AgreementCheckbox(
          value: agreed,
          label: tr(OnboardingStringKeys.agreeCheckbox),
          onChanged: onAgreedChanged,
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            onPressed: onContinue,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textOnPrimary,
              disabledBackgroundColor: AppColors.border,
              disabledForegroundColor: AppColors.textSecondary,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              tr(OnboardingStringKeys.continueButton),
              style: AppTypography.caption(
                color: agreed ? AppColors.textOnPrimary : AppColors.textSecondary,
                fontWeight: FontWeight.w700,
              ).copyWith(fontSize: 15),
            ),
          ),
        ),
      ],
    );
  }
}

class _LegalSection extends StatelessWidget {
  const _LegalSection({
    required this.title,
    required this.body,
    required this.viewLabel,
  });

  final String title;
  final String body;
  final String viewLabel;

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
                child: Text(title, style: AppTypography.heading(fontSize: 16)),
              ),
              TextButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('$viewLabel: $title'),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      margin: const EdgeInsets.all(16),
                    ),
                  );
                },
                child: Text(
                  viewLabel,
                  style: AppTypography.caption(color: AppColors.accent)
                      .copyWith(fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: AppTypography.productMeta().copyWith(
              fontSize: 13,
              height: 1.5,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionsSection extends StatelessWidget {
  const _PermissionsSection({
    required this.title,
    required this.items,
  });

  final String title;
  final List<(IconData, String)> items;

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
          Text(title, style: AppTypography.heading(fontSize: 16)),
          const SizedBox(height: 12),
          for (var i = 0; i < items.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(items[i].$1, size: 20, color: AppColors.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    items[i].$2,
                    style: AppTypography.productMeta().copyWith(fontSize: 13),
                  ),
                ),
              ],
            ),
            if (i < items.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _AgreementCheckbox extends StatelessWidget {
  const _AgreementCheckbox({
    required this.value,
    required this.label,
    required this.onChanged,
  });

  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardBackground,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: value ? AppColors.accent : AppColors.border,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 24,
                height: 24,
                child: Checkbox(
                  value: value,
                  onChanged: (checked) => onChanged(checked ?? false),
                  activeColor: AppColors.accent,
                  checkColor: AppColors.textOnAccent,
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  style: AppTypography.caption(fontWeight: FontWeight.w500)
                      .copyWith(fontSize: 12, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AuthStep extends StatelessWidget {
  const _AuthStep({
    super.key,
    required this.tr,
    required this.language,
    required this.showApple,
    required this.onGoogle,
    required this.onApple,
    required this.onSkip,
  });

  final String Function(String key) tr;
  final AppLanguage language;
  final bool showApple;
  final VoidCallback onGoogle;
  final VoidCallback onApple;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                Container(
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
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.background,
                          border: Border.all(color: AppColors.accent, width: 1.5),
                        ),
                        child: const Icon(
                          Icons.diamond_outlined,
                          size: 36,
                          color: AppColors.accent,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        tr(OnboardingStringKeys.authTitle),
                        style: AppTypography.heading(fontSize: 24),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        tr(OnboardingStringKeys.authSubtitle),
                        textAlign: TextAlign.center,
                        style: AppTypography.productMeta().copyWith(fontSize: 14),
                      ),
                      const SizedBox(height: 24),
                      SocialAuthButton(
                        label: tr(OnboardingStringKeys.signInGoogle),
                        onPressed: onGoogle,
                        icon: Container(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          child: Text(
                            'G',
                            style: AppTypography.caption(fontWeight: FontWeight.w700)
                                .copyWith(
                              fontSize: 14,
                              color: const Color(0xFF4285F4),
                            ),
                          ),
                        ),
                      ),
                      if (showApple) ...[
                        const SizedBox(height: 12),
                        SocialAuthButton(
                          label: tr(OnboardingStringKeys.signInApple),
                          onPressed: onApple,
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.textOnPrimary,
                          borderColor: AppColors.primary,
                          icon: const Icon(
                            Icons.apple,
                            size: 22,
                            color: AppColors.textOnPrimary,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 48,
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: onSkip,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textPrimary,
                            side: const BorderSide(color: AppColors.border),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            tr(OnboardingStringKeys.skipGuest),
                            style: AppTypography.caption(
                              fontWeight: FontWeight.w600,
                            ).copyWith(fontSize: 14),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Center(child: FeedbackButton(language: language)),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }
}
