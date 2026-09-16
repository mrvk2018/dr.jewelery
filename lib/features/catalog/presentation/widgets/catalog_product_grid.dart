import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../home/presentation/widgets/product_card.dart';
import '../../../../shared/models/product_item.dart';

/// Общие параметры сетки витрины (каталог / главная).
abstract final class ProductGridLayout {
  /// Ширина/высота ячейки. 0.58 не хватало места под блок текста + кнопку в [ProductCard].
  static const delegate = SliverGridDelegateWithFixedCrossAxisCount(
    crossAxisCount: 2,
    crossAxisSpacing: 12,
    mainAxisSpacing: 12,
    childAspectRatio: 0.50,
  );
}

/// Слайвер-сетка товаров каталога с ленивой отрисовкой карточек.
class CatalogProductGrid extends StatelessWidget {
  const CatalogProductGrid({
    super.key,
    required this.products,
  });

  final List<ProductItem> products;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 48),
          child: Column(
            children: [
              Icon(
                Icons.search_off_rounded,
                size: 48,
                color: AppColors.textSecondary.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 12),
              Text(
                'Ничего не найдено',
                style: AppTypography.heading(fontSize: 18),
              ),
              const SizedBox(height: 4),
              Text(
                'Попробуйте изменить фильтры или поисковый запрос',
                textAlign: TextAlign.center,
                style: AppTypography.productMetaStyle.copyWith(fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: ProductGridLayout.delegate,
        delegate: SliverChildBuilderDelegate(
          (context, index) => ProductCard(product: products[index]),
          childCount: products.length,
        ),
      ),
    );
  }
}
