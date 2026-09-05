import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/product_item.dart';

/// Виджет рассрочки «Долями» в стиле Sunlight.
class ProductInstallmentBanner extends StatelessWidget {
  const ProductInstallmentBanner({
    super.key,
    required this.product,
  });

  final ProductItem product;

  @override
  Widget build(BuildContext context) {
    final payment = (product.salePrice / 4).round();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.installmentMintBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.installmentMint.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.installmentMint.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.payments_outlined,
              color: AppColors.installmentMint,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Оплата Долями',
                  style: AppTypography.caption(fontWeight: FontWeight.w700)
                      .copyWith(fontSize: 14, color: AppColors.primary),
                ),
                const SizedBox(height: 2),
                Text(
                  '4 платежа по ${formatRubPrice(payment)}',
                  style: AppTypography.productMeta().copyWith(
                    fontSize: 13,
                    color: AppColors.installmentMint,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              '0%',
              style: AppTypography.caption(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ).copyWith(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
