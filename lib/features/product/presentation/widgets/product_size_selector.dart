import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/product_item.dart';

/// Размеры по умолчанию для экрана детальной карточки.
const defaultDetailRingSizes = <double>[16, 16.5, 17, 17.5];

List<double> resolveProductSizes(ProductItem product) {
  if (product.category != 'Кольца') return const [];
  if (product.availableSizes.isEmpty) return defaultDetailRingSizes;
  final filtered = product.availableSizes
      .where(defaultDetailRingSizes.contains)
      .toList()
    ..sort();
  return filtered.isEmpty ? defaultDetailRingSizes : filtered;
}

String formatSizeLabel(double size) {
  return size % 1 == 0 ? size.toInt().toString() : size.toString();
}

/// Горизонтальный выбор размера украшения.
class ProductSizeSelector extends StatelessWidget {
  const ProductSizeSelector({
    super.key,
    required this.sizes,
    required this.selectedSize,
    required this.onSizeSelected,
    this.onSizeGuideTap,
  });

  final List<double> sizes;
  final double? selectedSize;
  final ValueChanged<double> onSizeSelected;
  final VoidCallback? onSizeGuideTap;

  @override
  Widget build(BuildContext context) {
    if (sizes.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Размер',
          style: AppTypography.heading(fontSize: 18),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 48,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: sizes.length,
            separatorBuilder: (context, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final size = sizes[index];
              final isSelected = selectedSize == size;

              return Material(
                color: isSelected
                    ? AppColors.accent.withValues(alpha: 0.15)
                    : AppColors.cardBackground,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => onSizeSelected(size),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isSelected ? AppColors.accent : AppColors.border,
                        width: isSelected ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      formatSizeLabel(size),
                      style: AppTypography.caption(
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textPrimary,
                      ).copyWith(fontSize: 13),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onSizeGuideTap,
          child: Text(
            'Как узнать свой размер?',
            style: AppTypography.caption(color: AppColors.accent).copyWith(
              fontSize: 12,
              decoration: TextDecoration.underline,
              decorationColor: AppColors.accent,
            ),
          ),
        ),
      ],
    );
  }
}
