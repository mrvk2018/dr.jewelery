import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// Кнопка привязки Google / Apple (профиль).
class ProfileSocialLinkButton extends StatelessWidget {
  const ProfileSocialLinkButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.backgroundColor = AppColors.background,
    this.foregroundColor = AppColors.textPrimary,
    this.borderColor = AppColors.border,
    this.isLoading = false,
  });

  final String label;
  final Widget icon;
  final VoidCallback? onPressed;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color borderColor;
  final bool isLoading;

  factory ProfileSocialLinkButton.google({
    required String label,
    required VoidCallback? onPressed,
    bool isLoading = false,
  }) {
    return ProfileSocialLinkButton(
      label: label,
      onPressed: onPressed,
      isLoading: isLoading,
      icon: Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
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

  factory ProfileSocialLinkButton.apple({
    required String label,
    required VoidCallback? onPressed,
    bool isLoading = false,
  }) {
    return ProfileSocialLinkButton(
      label: label,
      onPressed: onPressed,
      isLoading: isLoading,
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
        onPressed: isLoading ? null : onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: backgroundColor,
          foregroundColor: foregroundColor,
          side: BorderSide(color: borderColor),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        child: isLoading
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: foregroundColor,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  icon,
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption(fontWeight: FontWeight.w600)
                          .copyWith(fontSize: 14, color: foregroundColor),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
