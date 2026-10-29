import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/product_item.dart';
import '../../../../shared/providers/favorites_controller.dart';
import '../../../../shared/providers/favorites_scope.dart';
import '../../../catalog/presentation/widgets/catalog_product_grid.dart';
import '../../../home/presentation/widgets/product_card.dart';

/// Вкладка избранного: карточки по id с Supabase.
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  Future<List<ProductItem>>? _productsFuture;
  FavoritesController? _favorites;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final favorites = FavoritesScope.of(context);
    if (!identical(_favorites, favorites)) {
      _favorites?.removeListener(_onFavoritesChanged);
      _favorites = favorites;
      favorites.addListener(_onFavoritesChanged);
      _reload();
    }
  }

  @override
  void dispose() {
    _favorites?.removeListener(_onFavoritesChanged);
    super.dispose();
  }

  void _onFavoritesChanged() {
    if (_favorites?.isResolving ?? false) return;
    _reload();
  }

  void _reload() {
    final favorites = _favorites;
    if (favorites == null) return;
    setState(() {
      _productsFuture = favorites.resolveProductsFromServer();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final favorites = FavoritesScope.of(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          l10n.favorites,
          style: AppTypography.heading(fontSize: 24),
        ),
      ),
      body: FutureBuilder<List<ProductItem>>(
        future: _productsFuture,
        builder: (context, snapshot) {
          if ((favorites.isResolving || favorites.isLoading) &&
              snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          final products = snapshot.data ?? [];
          if (products.isEmpty) {
            return _FavoritesEmptyView(
              title: l10n.favoritesEmptyTitle,
              subtitle: l10n.favoritesEmptySubtitle,
            );
          }

          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: products.length,
            gridDelegate: ProductGridLayout.delegate,
            itemBuilder: (context, index) {
              return ProductCard(product: products[index]);
            },
          );
        },
      ),
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
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.favorite_border_rounded,
              size: 56,
              color: AppColors.textSecondary.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 16),
            Text(title, style: AppTypography.heading(fontSize: 20)),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppTypography.productMetaStyle.copyWith(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
