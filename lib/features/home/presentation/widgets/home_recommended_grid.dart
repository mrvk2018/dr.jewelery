import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../shared/providers/catalog_scope.dart';
import '../../../catalog/presentation/widgets/catalog_product_grid.dart';
import 'product_card.dart';

/// Слайвер-сетка рекомендуемых товаров под промо-баннером.
class HomeRecommendedGrid extends StatelessWidget {
  const HomeRecommendedGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final items = CatalogScope.of(context).products;
    if (items.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFFF9F9F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0E0E0)),
            ),
            child: Text(
              'Скоро появятся новые коллекции',
              textAlign: TextAlign.center,
              style: AppTypography.productMetaStyle.copyWith(fontSize: 14),
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverGrid(
        gridDelegate: ProductGridLayout.delegate,
        delegate: SliverChildBuilderDelegate(
          (context, index) => ProductCard(product: items[index]),
          childCount: items.length,
        ),
      ),
    );
  }
}

/// Заголовок секции «Рекомендуем для вас».
class HomeRecommendedTitle extends StatelessWidget {
  const HomeRecommendedTitle({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          'Рекомендуем для вас',
          style: AppTypography.heading(fontSize: 22),
        ),
      ),
    );
  }
}
