import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/product_gallery_urls.dart';
List<String> adminProductImageUrls(Map<String, dynamic> row) =>
    productGalleryImageUrls(row);

List<String> posCartProductImageUrlsFromProduct({
  required List<String> images,
  String? imageUrl,
}) {
  if (images.isNotEmpty) return images;
  final url = imageUrl?.trim();
  if (url != null && url.isNotEmpty) return [url];
  return const [];
}

Future<void> showAdminProductPhotoPreview(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<String> imageUrls,
  int initialIndex = 0,
}) async {
  final urls = imageUrls
      .map((u) => u.trim())
      .where((u) => u.isNotEmpty)
      .toList();
  if (urls.isEmpty) return;
  final start = initialIndex.clamp(0, urls.length - 1);

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.72),
    builder: (ctx) => AdminProductPhotoPreviewDialog(
      title: title,
      subtitle: subtitle,
      imageUrls: urls,
      initialIndex: start,
    ),
  );
}

class AdminProductPhotoPreviewDialog extends StatefulWidget {
  const AdminProductPhotoPreviewDialog({
    super.key,
    required this.title,
    required this.imageUrls,
    this.subtitle,
    this.initialIndex = 0,
  });

  final String title;
  final String? subtitle;
  final List<String> imageUrls;
  final int initialIndex;

  @override
  State<AdminProductPhotoPreviewDialog> createState() =>
      _AdminProductPhotoPreviewDialogState();
}

class _AdminProductPhotoPreviewDialogState
    extends State<AdminProductPhotoPreviewDialog> {
  late final PageController _pageController;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.imageUrls.length - 1);
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _close() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.imageUrls;
    final size = MediaQuery.sizeOf(context);
    final maxWidth = size.width.clamp(280.0, 720.0);
    final imageHeight = (size.height * 0.62).clamp(260.0, 560.0);

    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: {
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              _close();
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 20),
            backgroundColor: AppColors.cardBackground,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.title,
                            style: AppTypography.heading(fontSize: 16),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Закрыть',
                          onPressed: _close,
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    if (widget.subtitle != null &&
                        widget.subtitle!.trim().isNotEmpty) ...[
                      Text(
                        widget.subtitle!,
                        style: AppTypography.productMeta(),
                      ),
                    ],
                    if (urls.length > 1) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Фото ${_index + 1} из ${urls.length}',
                        style: AppTypography.productMeta(),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      height: imageHeight,
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: urls.length,
                        onPageChanged: (i) => setState(() => _index = i),
                        itemBuilder: (context, index) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Image.network(
                              urls[index],
                              fit: BoxFit.contain,
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              },
                              errorBuilder: (_, _, _) => const Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  size: 48,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    if (urls.length > 1) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            tooltip: 'Предыдущее',
                            onPressed: _index > 0
                                ? () => _pageController.previousPage(
                                      duration: const Duration(milliseconds: 220),
                                      curve: Curves.easeOut,
                                    )
                                : null,
                            icon: const Icon(Icons.chevron_left),
                          ),
                          ...List.generate(urls.length, (i) {
                            final active = i == _index;
                            return Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 2),
                              child: Icon(
                                Icons.circle,
                                size: active ? 9 : 7,
                                color: active
                                    ? AppColors.primary
                                    : AppColors.textSecondary
                                        .withValues(alpha: 0.4),
                              ),
                            );
                          }),
                          IconButton(
                            tooltip: 'Следующее',
                            onPressed: _index < urls.length - 1
                                ? () => _pageController.nextPage(
                                      duration: const Duration(milliseconds: 220),
                                      curve: Curves.easeOut,
                                    )
                                : null,
                            icon: const Icon(Icons.chevron_right),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AdminClickableNetworkThumbnail extends StatelessWidget {
  const AdminClickableNetworkThumbnail({
    super.key,
    required this.imageUrl,
    required this.size,
    this.onTap,
    this.tooltip = 'Открыть фото',
    this.borderRadius = 8,
  });

  final String? imageUrl;
  final double size;
  final VoidCallback? onTap;
  final String tooltip;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final child = DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: SizedBox(
          width: size,
          height: size,
          child: _buildImage(),
        ),
      ),
    );

    if (onTap == null || imageUrl == null || imageUrl!.trim().isEmpty) {
      return child;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          hoverColor: AppColors.primary.withValues(alpha: 0.06),
          splashColor: AppColors.primary.withValues(alpha: 0.12),
          child: Tooltip(
            message: tooltip,
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildImage() {
    final url = imageUrl?.trim();
    if (url == null || url.isEmpty) {
      return _placeholder(Icons.image_not_supported_outlined);
    }
    return Image.network(
      url,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              value: progress.expectedTotalBytes != null
                  ? progress.cumulativeBytesLoaded /
                      progress.expectedTotalBytes!
                  : null,
            ),
          ),
        );
      },
      errorBuilder: (_, _, _) => _placeholder(Icons.broken_image_outlined),
    );
  }

  Widget _placeholder(IconData icon) {
    return Center(
      child: Icon(
        icon,
        size: size * 0.42,
        color: AppColors.textSecondary.withValues(alpha: 0.55),
      ),
    );
  }
}