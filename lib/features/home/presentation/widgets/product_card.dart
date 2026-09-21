import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/l10n/localized_text.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/product_item.dart';
import '../../../../shared/providers/cart_scope.dart';
import '../../../../shared/providers/favorites_scope.dart';
import '../../../../shared/widgets/out_of_stock_plaque.dart';
import '../../../../shared/widgets/product_image.dart';
import '../../../product/presentation/pages/product_detail_screen.dart';
import '../../../product/presentation/widgets/product_size_selector.dart';

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
  String? _sizeWeightLabel(BuildContext context, ProductItem product) {
    final parts = <String>[];
    if (product.availableSizes.isNotEmpty) {
      parts.add(product.availableSizes.first.toString());
    }
    final grams = product.weightGrams;
    if (grams != null) {
      final rounded = grams == grams.roundToDouble()
          ? grams.toInt().toString()
          : grams.toString();
      parts.add(context.l10n.productWeightGrams(rounded));
    }
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }

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

    CartScope.of(context).addProduct(
      product: widget.product,
      selectedSize: defaultSelectedProductSize(widget.product),
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.productAddedToCart),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
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
                    ProductImage(product: product),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: _DiscountBadge(
                        label:
                            '-${displayDiscountPercentForProduct(product)}%',
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
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PriceRow(
                        salePrice: product.salePrice,
                        displayOldPrice: displayOldPriceForProduct(product),
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Flexible(
                              child: Text(
                                displayName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.productTitle,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Flexible(
                              child: Text(
                                LocalizedText.attribute(
                                  product.metal,
                                  languageCode: currentLang,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.productMetaStyle,
                              ),
                            ),
                            if (_sizeWeightLabel(context, product) != null) ...[
                              const SizedBox(height: 2),
                              Flexible(
                                child: Text(
                                  _sizeWeightLabel(context, product)!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.productMetaStyle,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      SizedBox(
                        width: double.infinity,
                        height: 34,
                        child: product.isOutOfStock
                            ? const OutOfStockPlaque(height: 34)
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
                                child: Text(context.l10n.addToCart),
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
    required this.displayOldPrice,
  });

  final int salePrice;
  final int displayOldPrice;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          formatWon(displayOldPrice),
          style: AppTypography.productOldPrice.copyWith(
            color: Colors.grey,
            decoration: TextDecoration.lineThrough,
            decorationColor: Colors.grey,
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            formatWon(salePrice),
            style: AppTypography.productPrice.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.accent,
            ),
          ),
        ),
      ],
    );
  }
}
