import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../shared/providers/catalog_scope.dart';
import 'product_card.dart';

/// Сетка рекомендуемых товаров под промо-баннером.
class HomeRecommendedGrid extends StatelessWidget {
  const HomeRecommendedGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final catalog = CatalogScope.of(context);

    return AnimatedBuilder(
      animation: catalog,
      builder: (context, _) {
        final items = catalog.products;
        if (items.isEmpty) {
          return Padding(
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
                style: AppTypography.productMeta().copyWith(fontSize: 14),
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.58,
            ),
            itemBuilder: (context, index) {
              return ProductCard(product: items[index]);
            },
          ),
        );
      },
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
