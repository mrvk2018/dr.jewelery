import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/l10n/payment_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// Экран неуспешной оплаты / отмены после Toss или Edge confirm.
class PaymentFailureScreen extends StatelessWidget {
  const PaymentFailureScreen({
    super.key,
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    String tr(String key) => paymentTr(key, context.langCode);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          tr(PaymentStringKeys.paymentFailed),
          style: AppTypography.heading(fontSize: 20),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 64,
                color: AppColors.saleRed,
              ),
              const SizedBox(height: 16),
              Text(
                tr(PaymentStringKeys.paymentFailed),
                style: AppTypography.heading(fontSize: 22),
              ),
              const SizedBox(height: 12),
              Text(
                message,
                style: AppTypography.productMeta().copyWith(
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).popUntil(
                    (route) => route.isFirst,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textOnPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(tr(PaymentStringKeys.backToHome)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
