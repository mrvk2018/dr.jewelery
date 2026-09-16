import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../shared/models/product_item.dart';
import '../../../../shared/widgets/product_image.dart';

/// Галерея изображений товара с индикатором страниц и кнопкой «Лайк».
class ProductGallery extends StatefulWidget {
  const ProductGallery({
    super.key,
    required this.product,
    required this.isFavorite,
    required this.onFavoriteToggle,
  });

  final ProductItem product;
  final bool isFavorite;
  final VoidCallback onFavoriteToggle;

  static const _placeholderIcons = [
    Icons.diamond_outlined,
    Icons.blur_circular_outlined,
    Icons.link_rounded,
    Icons.watch_outlined,
    Icons.favorite_border_rounded,
    Icons.circle_outlined,
    Icons.watch_rounded,
  ];

  @override
  State<ProductGallery> createState() => _ProductGalleryState();
}

class _ProductGalleryState extends State<ProductGallery> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = widget.product.imageUrl?.trim().isNotEmpty ?? false;
    final pageCount = hasPhoto ? 1 : 3;

    return SizedBox(
      height: 360,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: pageCount,
            onPageChanged: (index) => setState(() => _currentPage = index),
            itemBuilder: (context, index) {
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.cardBackground,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                clipBehavior: Clip.antiAlias,
                child: hasPhoto
                    ? ProductImage(
                        product: widget.product,
                        placeholderIconSize: 120,
                      )
                    : Center(
                        child: Icon(
                          ProductGallery._placeholderIcons[widget
                                      .product.iconIndex %
                                  ProductGallery._placeholderIcons.length],
                          size: 120,
                          color: AppColors.accent.withValues(alpha: 0.45),
                        ),
                      ),
              );
            },
          ),
          Positioned(
            top: 16,
            right: 28,
            child: _GalleryFavoriteButton(
              isFavorite: widget.isFavorite,
              onTap: widget.onFavoriteToggle,
            ),
          ),
          if (pageCount > 1)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(pageCount, (index) {
                  final isActive = index == _currentPage;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: isActive ? 20 : 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: isActive
                          ? AppColors.accent
                          : AppColors.textSecondary.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}

class _GalleryFavoriteButton extends StatelessWidget {
  const _GalleryFavoriteButton({
    required this.isFavorite,
    required this.onTap,
  });

  final bool isFavorite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background.withValues(alpha: 0.94),
      shape: const CircleBorder(),
      elevation: 2,
      shadowColor: AppColors.primary.withValues(alpha: 0.12),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: isFavorite ? AppColors.saleRed : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
