import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// Премиальная кнопка входа через Google или Apple.
class SocialAuthButton extends StatelessWidget {
  const SocialAuthButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.backgroundColor = AppColors.background,
    this.foregroundColor = AppColors.textPrimary,
    this.borderColor = AppColors.border,
  });

  final String label;
  final Widget icon;
  final VoidCallback onPressed;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color borderColor;

  factory SocialAuthButton.google({required VoidCallback onPressed}) {
    return SocialAuthButton(
      label: 'Войти через Google',
      onPressed: onPressed,
      icon: Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'G',
          style: AppTypography.caption(fontWeight: FontWeight.w700).copyWith(
            fontSize: 14,
            color: const Color(0xFF4285F4),
          ),
        ),
      ),
    );
  }

  factory SocialAuthButton.apple({required VoidCallback onPressed}) {
    return SocialAuthButton(
      label: 'Войти через Apple',
      onPressed: onPressed,
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.textOnPrimary,
      borderColor: AppColors.primary,
      icon: const Icon(
        Icons.apple,
        size: 22,
        color: AppColors.textOnPrimary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          side: BorderSide(color: borderColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 12),
            Text(
              label,
              style: AppTypography.caption(fontWeight: FontWeight.w600)
                  .copyWith(fontSize: 14, color: foregroundColor),
            ),
          ],
        ),
      ),
    );
  }
}
