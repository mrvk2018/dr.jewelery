import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/providers/catalog_scope.dart';
import '../../../../shared/providers/favorites_scope.dart';
import '../../../catalog/presentation/widgets/catalog_product_grid.dart';
import '../../../home/presentation/widgets/product_card.dart';

/// Вкладка избранного: сетка товаров или пустое состояние.
class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final favorites = FavoritesScope.of(context);
    final catalog = CatalogScope.of(context);

    return ListenableBuilder(
      listenable: Listenable.merge([favorites, catalog]),
      builder: (context, _) {
        final products = favorites.resolveProducts(catalog.products);

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Text(
              l10n.favorites,
              style: AppTypography.heading(fontSize: 24),
            ),
          ),
          body: products.isEmpty
              ? _FavoritesEmptyView(
                  title: l10n.favoritesEmptyTitle,
                  subtitle: l10n.favoritesEmptySubtitle,
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  itemCount: products.length,
                  gridDelegate: ProductGridLayout.delegate,
                  itemBuilder: (context, index) {
                    return ProductCard(product: products[index]);
                  },
                ),
        );
      },
    );
  }
}

class _FavoritesEmptyView extends StatelessWidget {
  const _FavoritesEmptyView({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.accent.withValues(alpha: 0.12),
                border: Border.all(color: AppColors.accent, width: 1.5),
              ),
              child: const Icon(
                Icons.favorite_rounded,
                size: 42,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.heading(fontSize: 22),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTypography.productMeta().copyWith(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
