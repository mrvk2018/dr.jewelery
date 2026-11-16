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

List<String> productGalleryImageUrls(Map<String, dynamic> row) {
  final fromAdditional = parseAdditionalImagesField(row['additional_images']);
  if (fromAdditional.isNotEmpty) {
    return fromAdditional.take(ProductItem.maxGalleryImages).toList();
  }
  final legacyUrl = row['image_url']?.toString().trim() ?? '';
  if (legacyUrl.isNotEmpty) {
    return [legacyUrl];
  }
  return const [];
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