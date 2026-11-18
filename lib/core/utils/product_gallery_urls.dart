import 'dart:convert';

import '../../shared/models/product_item.dart';

String normalizeProductSku(String sku) => sku.trim().toLowerCase();

List<String> parseAdditionalImagesField(Object? raw) {
  if (raw == null) return const [];
  if (raw is List) {
    return raw
        .map((e) => e.toString().trim())
        .where((url) => url.isNotEmpty)
        .toList();
  }
  if (raw is String) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const [];
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is List) {
        return decoded
            .map((e) => e.toString().trim())
            .where((url) => url.isNotEmpty)
            .toList();
      }
      if (decoded is String && decoded.trim().isNotEmpty) {
        return [decoded.trim()];
      }
    } catch (_) {
      if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
        return [trimmed];
      }
      return const [];
    }
  }
  return const [];
}

/// Поля `products` для записи галереи (первый URL → `image_url`, полный список в оба массива).
Map<String, dynamic> productGalleryDbFieldsFromUrls(
  Iterable<String> urls, {
  int maxCount = ProductItem.maxGalleryImages,
}) {
  final normalized = mergeUniqueGalleryUrls(urls, maxCount: maxCount);
  if (normalized.isEmpty) {
    return {
      'image_url': null,
      'images': const <String>[],
      'additional_images': const <String>[],
    };
  }
  return {
    'image_url': normalized.first,
    'images': normalized,
    'additional_images': normalized,
  };
}

List<String> productGalleryImageUrls(Map<String, dynamic> row) {
  final primary = row['image_url']?.toString().trim() ?? '';
  final fromImages = parseAdditionalImagesField(row['images']);
  final fromAdditional = parseAdditionalImagesField(row['additional_images']);
  return mergeUniqueGalleryUrls([
    if (primary.isNotEmpty) primary,
    ...fromImages,
    ...fromAdditional,
  ]);
}

List<String> productGalleryImageUrlsFromClientJson(Map<String, dynamic> json) {
  final primary =
      json['imageUrl'] as String? ?? json['image_url'] as String? ?? '';
  final fromImages = parseAdditionalImagesField(json['images']);
  final fromAdditional = parseAdditionalImagesField(
    json['additionalImages'] ?? json['additional_images'],
  );
  return mergeUniqueGalleryUrls([
    if (primary.trim().isNotEmpty) primary.trim(),
    ...fromImages,
    ...fromAdditional,
  ]);
}

List<String> mergeUniqueGalleryUrls(
  Iterable<String> urls, {
  int maxCount = ProductItem.maxGalleryImages,
}) {
  final seen = <String>{};
  final merged = <String>[];
  for (final raw in urls) {
    final url = raw.trim();
    if (url.isEmpty || seen.contains(url)) continue;
    seen.add(url);
    merged.add(url);
    if (merged.length >= maxCount) break;
  }
  return merged;
}

List<String> findGalleryUrlsInCatalogRows(
  String sku,
  Iterable<Map<String, dynamic>> rows,
) {
  final needle = normalizeProductSku(sku);
  if (needle.isEmpty) return const [];

  final collected = <String>[];
  for (final row in rows) {
    final rowSku = normalizeProductSku(row['sku']?.toString() ?? '');
    if (rowSku != needle) continue;
    collected.addAll(productGalleryImageUrls(row));
  }
  return mergeUniqueGalleryUrls(collected);
}

List<String> mergeGalleryUrlsFromProductRows(
  Iterable<Map<String, dynamic>> rows,
) {
  final collected = <String>[];
  for (final row in rows) {
    collected.addAll(productGalleryImageUrls(row));
  }
  return mergeUniqueGalleryUrls(collected);
}