import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/product_item.dart';
import '../../../../shared/providers/cart_scope.dart';
import '../../../../shared/providers/locale_provider.dart';
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
  bool _isFavorite = false;
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

  void _addToCart() {
    if (_requiresSize && _selectedSize == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите размер изделия')),
      );
      return;
    }

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

  @override
  Widget build(BuildContext context) {
    final languageCode = LocaleScope.of(context).languageCode;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          product.category,
          style: AppTypography.heading(fontSize: 18),
        ),
      ),
      bottomNavigationBar: _AddToCartBar(onPressed: _addToCart),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            ProductGallery(
              product: product,
              isFavorite: _isFavorite,
              onFavoriteToggle: () => setState(() => _isFavorite = !_isFavorite),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.localizedName(languageCode),
                    style: AppTypography.heading(fontSize: 24),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${product.metal} · ${product.insert}',
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
                    'Описание',
                    style: AppTypography.heading(fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _buildDescription(product, languageCode),
                    style: AppTypography.productMeta().copyWith(
                      fontSize: 14,
                      height: 1.5,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Характеристики',
                    style: AppTypography.heading(fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  _SpecRow(label: 'Категория', value: product.category),
                  _SpecRow(label: 'Металл', value: product.metal),
                  _SpecRow(label: 'Вставка', value: product.insert),
                  _SpecRow(
                    label: 'Артикул',
                    value: 'SL-${product.id.padLeft(4, '0')}',
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

  String _buildDescription(ProductItem product, String languageCode) {
    final localized = product.localizedDescription(languageCode);
    if (localized.isNotEmpty) return localized;
    return 'Изысканное украшение из коллекции Sunlight. '
        '${product.localizedName(languageCode)} выполнено из ${product.metal.toLowerCase()} '
        'с ${product.insert == 'Без вставок' ? 'лаконичным дизайном без вставок' : 'вставкой: ${product.insert.toLowerCase()}'}.' 
        ' Идеально подходит для особых моментов и ежедневного образа.';
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
          formatRubPrice(salePrice),
          style: AppTypography.price(
            fontSize: 28,
            color: AppColors.saleRed,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          formatRubPrice(oldPrice),
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

class _AddToCartBar extends StatelessWidget {
  const _AddToCartBar({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 48,
          width: double.infinity,
          child: ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textOnPrimary,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: AppTypography.caption(
                color: AppColors.textOnPrimary,
                fontWeight: FontWeight.w700,
              ).copyWith(fontSize: 15),
            ),
            child: const Text('Добавить в корзину'),
          ),
        ),
      ),
    );
  }
}
