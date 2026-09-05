import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// Полноэкранный индикатор симуляции App-to-App оплаты.
class PaymentLoadingOverlay extends StatelessWidget {
  const PaymentLoadingOverlay({
    super.key,
    required this.message,
  });

  final String message;

  static Future<void> show(
    BuildContext context, {
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: AppColors.primary.withValues(alpha: 0.92),
      builder: (_) => PaymentLoadingOverlay(message: message),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.background.withValues(alpha: 0.08),
                  border: Border.all(color: AppColors.accent, width: 2),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: AppColors.accent,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppTypography.heading(
                  fontSize: 18,
                  color: AppColors.textOnPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'App-to-App',
                style: AppTypography.caption(
                  color: AppColors.accent,
                  fontWeight: FontWeight.w600,
                ).copyWith(fontSize: 13, letterSpacing: 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
