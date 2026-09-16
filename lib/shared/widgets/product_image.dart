import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../models/product_item.dart';

/// Фото товара из Supabase Storage или декоративная заглушка.
class ProductImage extends StatelessWidget {
  const ProductImage({
    super.key,
    required this.product,
    this.fit = BoxFit.cover,
    this.placeholderIconSize = 48,
    this.placeholderAlignment = Alignment.center,
  });

  final ProductItem product;
  final BoxFit fit;
  final double placeholderIconSize;
  final Alignment placeholderAlignment;

  static const _placeholderIcons = [
    Icons.diamond_outlined,
    Icons.blur_circular_outlined,
    Icons.link_rounded,
    Icons.watch_outlined,
    Icons.favorite_border_rounded,
    Icons.circle_outlined,
    Icons.watch_rounded,
  ];

  String? get _url {
    final raw = product.imageUrl?.trim();
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  Widget _placeholder() {
    final icon =
        _placeholderIcons[product.iconIndex % _placeholderIcons.length];
    return ColoredBox(
      color: AppColors.cardBackground,
      child: Align(
        alignment: placeholderAlignment,
        child: Icon(
          icon,
          size: placeholderIconSize,
          color: AppColors.accent.withValues(alpha: 0.55),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final url = _url;
    if (url == null) {
      return _placeholder();
    }

    return Image.network(
      url,
      fit: fit,
      width: double.infinity,
      height: double.infinity,
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) return child;
        return ColoredBox(
          color: AppColors.cardBackground,
          child: Center(
            child: SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.accent,
                value: loadingProgress.expectedTotalBytes != null
                    ? loadingProgress.cumulativeBytesLoaded /
                        loadingProgress.expectedTotalBytes!
                    : null,
              ),
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) => _placeholder(),
    );
  }
}
