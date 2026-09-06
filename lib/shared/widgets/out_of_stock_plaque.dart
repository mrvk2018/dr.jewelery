import 'package:flutter/material.dart';

import '../../core/extensions/context_extensions.dart';
import '../../core/l10n/stock_localizations.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// Люксовая плашка «Нет в наличии» вместо кнопки покупки.
class OutOfStockPlaque extends StatelessWidget {
  const OutOfStockPlaque({
    super.key,
    this.height = 36,
  });

  final double height;

  @override
  Widget build(BuildContext context) {
    final label = outOfStockLabelForCode(context.langCode);

    return Container(
      height: height,
      width: double.infinity,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.accent, width: 1.2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.remove_shopping_cart_outlined,
            size: height >= 44 ? 18 : 14,
            color: AppColors.accent,
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption(
                color: AppColors.accent,
                fontWeight: FontWeight.w700,
              ).copyWith(
                fontSize: height >= 44 ? 14 : 11,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
