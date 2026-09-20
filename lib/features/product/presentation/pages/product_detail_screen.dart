import 'package:flutter/material.dart';

import '../../../checkout/presentation/pages/checkout_screen.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../shared/providers/cart_controller.dart';
import '../../../../core/l10n/localized_text.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/product_item.dart';
import '../../../../shared/providers/cart_scope.dart';
import '../../../../shared/providers/favorites_scope.dart';
import '../../../../shared/widgets/out_of_stock_plaque.dart';
import '../widgets/product_gallery.dart';
import '../widgets/product_installment_banner.dart';
import '../widgets/product_size_selector.dart';

/// Детальная карточка ювелирного изделия.
class ProductDetailScreen extends StatefulWidget {
  const ProductDetailScreen({
    super.key,
    required this.product,
  });

  final ProductItem product;

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  double? _selectedSize;

  ProductItem get product => widget.product;

  List<double> get _sizes => resolveProductSizes(product);

  bool get _requiresSize => _sizes.isNotEmpty;

  @override
  void initState() {
    super.initState();
    if (_sizes.isNotEmpty) {
      _selectedSize = _sizes.first;
    }
  }

  bool _ensureCanPurchase() {
    if (product.isOutOfStock) return false;
    if (_requiresSize && _selectedSize == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите размер изделия')),
      );
      return false;
    }
    return true;
  }

  void _addToCart() {
    if (!_ensureCanPurchase()) return;

    CartScope.of(context).addProduct(
      product: product,
      selectedSize: _selectedSize,
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Товар добавлен в корзину'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        action: SnackBarAction(
          label: 'OK',
          onPressed: () {},
        ),
      ),
    );
  }

  void _buyNow() {
    if (!_ensureCanPurchase()) return;

    final buyNowLine = CartItem(
      product: product,
      selectedSize: _selectedSize,
      quantity: 1,
    );

    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => CheckoutScreen(
          productsTotal: buyNowLine.lineTotal,
          checkoutItems: [buyNowLine],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final languageCode = context.langCode;
    final favorites = FavoritesScope.of(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          LocalizedText.attribute(product.category, languageCode: languageCode),
          style: AppTypography.heading(fontSize: 18),
        ),
      ),
      bottomNavigationBar: _ProductActionBar(
        isOutOfStock: product.isOutOfStock,
        onAddToCart: product.isOutOfStock ? null : _addToCart,
        onBuyNow: product.isOutOfStock ? null : _buyNow,
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            ProductGallery(
              product: product,
              isFavorite: favorites.isFavorite(product),
              onFavoriteToggle: () => favorites.toggleFavorite(product),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.nameTranslations[languageCode] ??
                        product.nameTranslations['ru'] ??
                        '',
                    style: AppTypography.heading(fontSize: 24),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${LocalizedText.attribute(product.metal, languageCode: languageCode)} · ${LocalizedText.attribute(product.insert, languageCode: languageCode)}',
                    style: AppTypography.productMeta().copyWith(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  _DetailPriceRow(
                    salePrice: product.salePrice,
                    oldPrice: product.oldPrice,
                    discountPercent: product.discountPercent,
                  ),
                  const SizedBox(height: 20),
                  ProductSizeSelector(
                    sizes: _sizes,
                    selectedSize: _selectedSize,
                    onSizeSelected: (size) {
                      setState(() => _selectedSize = size);
                    },
                    onSizeGuideTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Гид по размерам будет доступен позже'),
                        ),
                      );
                    },
                  ),
                  if (_sizes.isNotEmpty) const SizedBox(height: 20),
                  ProductInstallmentBanner(product: product),
                  const SizedBox(height: 20),
                  Text(
                    LocalizedText.productDetail(
                      'description',
                      languageCode: languageCode,
                    ),
                    style: AppTypography.heading(fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    product.descriptionTranslations[languageCode] ??
                        product.descriptionTranslations['ru'] ??
                        '',
                    style: AppTypography.productMeta().copyWith(
                      fontSize: 14,
                      height: 1.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    LocalizedText.productDetail(
                      'specs',
                      languageCode: languageCode,
                    ),
                    style: AppTypography.heading(fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  _SpecRow(
                    label: LocalizedText.productDetail(
                      'category',
                      languageCode: languageCode,
                    ),
                    value: LocalizedText.attribute(
                      product.category,
                      languageCode: languageCode,
                    ),
                  ),
                  _SpecRow(
                    label: LocalizedText.productDetail(
                      'metal',
                      languageCode: languageCode,
                    ),
                    value: LocalizedText.attribute(
                      product.metal,
                      languageCode: languageCode,
                    ),
                  ),
                  _SpecRow(
                    label: LocalizedText.productDetail(
                      'insert',
                      languageCode: languageCode,
                    ),
                    value: LocalizedText.attribute(
                      product.insert,
                      languageCode: languageCode,
                    ),
                  ),
                  _SpecRow(
                    label: LocalizedText.productDetail(
                      'sku',
                      languageCode: languageCode,
                    ),
                    value: product.sku,
                  ),
                  _SpecRow(
                    label: LocalizedText.productDetail(
                      'stock',
                      languageCode: languageCode,
                    ),
                    value: product.isOutOfStock
                        ? '0'
                        : '${product.stockQuantity}',
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailPriceRow extends StatelessWidget {
  const _DetailPriceRow({
    required this.salePrice,
    required this.oldPrice,
    required this.discountPercent,
  });

  final int salePrice;
  final int oldPrice;
  final int discountPercent;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          formatWon(salePrice),
          style: AppTypography.price(
            fontSize: 28,
            color: AppColors.saleRed,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          formatWon(oldPrice),
          style: AppTypography.price(
            fontSize: 16,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w400,
            decoration: TextDecoration.lineThrough,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.saleBadge,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '-$discountPercent%',
            style: AppTypography.caption(
              color: AppColors.textOnPrimary,
              fontWeight: FontWeight.w700,
            ).copyWith(fontSize: 12),
          ),
        ),
      ],
    );
  }
}

class _SpecRow extends StatelessWidget {
  const _SpecRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: AppTypography.productMeta()),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTypography.caption(fontWeight: FontWeight.w500)
                  .copyWith(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductActionBar extends StatelessWidget {
  const _ProductActionBar({
    required this.isOutOfStock,
    required this.onAddToCart,
    required this.onBuyNow,
  });

  final bool isOutOfStock;
  final VoidCallback? onAddToCart;
  final VoidCallback? onBuyNow;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: isOutOfStock
            ? const SizedBox(
                height: 48,
                width: double.infinity,
                child: OutOfStockPlaque(height: 48),
              )
            : Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 48,
                      child: OutlinedButton.icon(
                        onPressed: onAddToCart,
                        icon: const Icon(Icons.shopping_bag_outlined, size: 20),
                        label: Text(l10n.addToCart),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: AppTypography.caption(
                            fontWeight: FontWeight.w700,
                          ).copyWith(fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: onBuyNow,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: AppColors.textOnAccent,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: AppTypography.caption(
                            color: AppColors.textOnAccent,
                            fontWeight: FontWeight.w700,
                          ).copyWith(fontSize: 15),
                        ),
                        child: Text(l10n.buyNow),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
