import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/l10n/localized_text.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/product_item.dart';
import '../../../../shared/providers/cart_scope.dart';
import '../../../../shared/providers/favorites_scope.dart';
import '../../../../shared/widgets/out_of_stock_plaque.dart';
import '../../../product/presentation/pages/product_detail_screen.dart';

/// Карточка товара для сетки рекомендаций на главном экране.
class ProductCard extends StatefulWidget {
  const ProductCard({
    super.key,
    required this.product,
    this.onAddToCart,
    this.onFavoriteToggle,
    this.onTap,
  });

  final ProductItem product;
  final VoidCallback? onAddToCart;
  final ValueChanged<bool>? onFavoriteToggle;
  final VoidCallback? onTap;

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  static const _placeholderIcons = [
    Icons.diamond_outlined,
    Icons.blur_circular_outlined,
    Icons.link_rounded,
    Icons.watch_outlined,
    Icons.favorite_border_rounded,
    Icons.circle_outlined,
    Icons.watch_rounded,
  ];

  void _openDetail() {
    if (widget.onTap != null) {
      widget.onTap!();
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProductDetailScreen(product: widget.product),
      ),
    );
  }

  void _handleAddToCart() {
    if (widget.product.isOutOfStock) return;
    if (widget.onAddToCart != null) {
      widget.onAddToCart!();
      return;
    }

    final sizes = widget.product.availableSizes;
    CartScope.of(context).addProduct(
      product: widget.product,
      selectedSize: sizes.isNotEmpty ? sizes.first : null,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Товар добавлен в корзину'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final icon = _placeholderIcons[product.iconIndex % _placeholderIcons.length];
    final currentLang = context.langCode;
    final displayName = product.nameTranslations[currentLang] ??
        product.nameTranslations['ru'] ??
        '';
    final favorites = FavoritesScope.of(context);
    final isFavorite = favorites.isFavorite(product);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _openDetail,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBackground, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: AppColors.cardBackground,
                      child: Icon(
                        icon,
                        size: 48,
                        color: AppColors.accent.withValues(alpha: 0.55),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: _DiscountBadge(
                        label: '-${product.discountPercent}%',
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 4,
                      child: _FavoriteButton(
                        isFavorite: isFavorite,
                        onTap: () {
                          favorites.toggleFavorite(product);
                          widget.onFavoriteToggle
                              ?.call(favorites.isFavorite(product));
                        },
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PriceRow(
                        salePrice: product.salePrice,
                        oldPrice: product.oldPrice,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        displayName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.productTitle,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        LocalizedText.attribute(
                          product.metal,
                          languageCode: currentLang,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.productMetaStyle,
                      ),
                      const Spacer(),
                      SizedBox(
                        width: double.infinity,
                        height: 36,
                        child: product.isOutOfStock
                            ? const OutOfStockPlaque()
                            : ElevatedButton(
                                onPressed: _handleAddToCart,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: AppColors.textOnPrimary,
                                  elevation: 0,
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  textStyle: AppTypography.productCartButton,
                                ),
                                child: const Text('В корзину'),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscountBadge extends StatelessWidget {
  const _DiscountBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.saleBadge,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: AppTypography.productDiscountBadge,
      ),
    );
  }
}

class _FavoriteButton extends StatelessWidget {
  const _FavoriteButton({
    required this.isFavorite,
    required this.onTap,
  });

  final bool isFavorite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background.withValues(alpha: 0.92),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 32,
          height: 32,
          child: Icon(
            isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            size: 18,
            color: isFavorite ? AppColors.saleRed : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _PriceRow extends StatelessWidget {
  const _PriceRow({
    required this.salePrice,
    required this.oldPrice,
  });

  final int salePrice;
  final int oldPrice;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      runSpacing: 2,
      children: [
        Text(
          formatWon(salePrice),
          style: AppTypography.productPrice,
        ),
        Text(
          formatWon(oldPrice),
          style: AppTypography.productOldPrice,
        ),
      ],
    );
  }
}
