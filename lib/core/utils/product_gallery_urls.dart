import 'dart:convert';

import '../../shared/models/product_item.dart';

/// Число фиксированных слотов галереи (совпадает с SQL `gallery_slots`).
const int kProductGallerySlotCount = ProductItem.maxGalleryImages;

const List<String> kProductGallerySlotLabels = [
  '1 · Главное',
  '2',
  '3',
  '4',
];

String normalizeProductSku(String sku) => sku.trim().toLowerCase();

String galleryUrlCanonical(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return '';
  final q = trimmed.indexOf('?');
  if (q <= 0) return trimmed;
  return trimmed.substring(0, q);
}

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

List<String?> parseGallerySlotsJson(Object? rawSlots) {
  final out = List<String?>.filled(kProductGallerySlotCount, null);
  if (rawSlots is! List) return out;
  for (var i = 0; i < kProductGallerySlotCount && i < rawSlots.length; i++) {
    final elem = rawSlots[i];
    if (elem == null) continue;
    final url = elem.toString().trim();
    if (url.isNotEmpty && url.toLowerCase() != 'null') {
      out[i] = url;
    }
  }
  return out;
}

List<String?> productGallerySlotsFromRow(Map<String, dynamic> row) {
  final fromColumn = parseGallerySlotsJson(row['gallery_slots']);
  if (fromColumn.any((u) => (u?.trim().isNotEmpty ?? false))) {
    return fromColumn;
  }
  return _gallerySlotsInitFromMergedUrls(productGalleryImageUrlsLegacy(row));
}

/// Подстановка фото из поиска по SKU: сначала в «родные» слоты, затем в пустые.
({int added, List<String?> slots}) mergeDiscoveredGalleryIntoSlots({
  required List<String?> current,
  List<String?>? sourceSlots,
  required List<String> extraUrls,
}) {
  final slots = List<String?>.from(current);
  final seen = <String>{
    for (final u in slots)
      if (u != null && u.trim().isNotEmpty) galleryUrlCanonical(u),
  };
  var added = 0;

  if (sourceSlots != null) {
    for (var i = 0; i < kProductGallerySlotCount; i++) {
      final src = i < sourceSlots.length ? sourceSlots[i]?.trim() : null;
      if (src == null || src.isEmpty) continue;
      if (i >= slots.length) break;
      if (slots[i] != null && slots[i]!.trim().isNotEmpty) continue;
      final canon = galleryUrlCanonical(src);
      if (canon.isNotEmpty && seen.contains(canon)) continue;
      slots[i] = src;
      if (canon.isNotEmpty) seen.add(canon);
      added++;
    }
  }

  for (final raw in extraUrls) {
    final url = raw.trim();
    if (url.isEmpty) continue;
    final canon = galleryUrlCanonical(url);
    if (canon.isNotEmpty && seen.contains(canon)) continue;
    final slot = firstEmptyGallerySlotIndex(slots);
    if (slot == null) break;
    if (canon.isNotEmpty) seen.add(canon);
    slots[slot] = url;
    added++;
  }

  return (added: added, slots: slots);
}

List<String?> _gallerySlotsInitFromMergedUrls(List<String> urls) {
  final slots = List<String?>.filled(kProductGallerySlotCount, null);
  final seen = <String>{};
  var slot = 0;
  for (final raw in urls) {
    if (slot >= kProductGallerySlotCount) break;
    final url = raw.trim();
    if (url.isEmpty) continue;
    final canon = galleryUrlCanonical(url);
    if (canon.isNotEmpty && seen.contains(canon)) continue;
    if (canon.isNotEmpty) seen.add(canon);
    slots[slot] = url;
    slot++;
  }
  return slots;
}

int countFilledGallerySlots(List<String?> slots) {
  var n = 0;
  for (final url in slots) {
    if (url != null && url.trim().isNotEmpty) n++;
  }
  return n;
}

int? firstEmptyGallerySlotIndex(List<String?> slots) {
  for (var i = 0; i < slots.length; i++) {
    final url = slots[i];
    if (url == null || url.trim().isEmpty) return i;
  }
  return null;
}

/// Меняет местами URL в двух фиксированных слотах (0..3).
void swapGallerySlotUrls(List<String?> slots, int a, int b) {
  if (a < 0 ||
      b < 0 ||
      a >= kProductGallerySlotCount ||
      b >= kProductGallerySlotCount ||
      a == b) {
    return;
  }
  final tmp = slots[a];
  slots[a] = slots[b];
  slots[b] = tmp;
}

/// Витринный список URL (без «дыр», порядок слотов 0→3).
List<String> productGalleryVitrineUrlsFromSlots(List<String?> slots) {
  final out = <String>[];
  for (final raw in slots) {
    final url = raw?.trim() ?? '';
    if (url.isNotEmpty) out.add(url);
  }
  return out;
}

String? productGalleryPrimaryUrlFromSlots(List<String?> slots) {
  for (final raw in slots) {
    final url = raw?.trim() ?? '';
    if (url.isNotEmpty) return url;
  }
  return null;
}

List<String> productGalleryImageUrlsLegacy(Map<String, dynamic> row) {
  final primary = row['image_url']?.toString().trim() ?? '';
  final fromImages = parseAdditionalImagesField(row['images']);
  final fromAdditional = parseAdditionalImagesField(row['additional_images']);
  return mergeUniqueGalleryUrls([
    if (primary.isNotEmpty) primary,
    ...fromImages,
    ...fromAdditional,
  ]);
}

List<String> productGalleryImageUrls(Map<String, dynamic> row) {
  final slots = productGallerySlotsFromRow(row);
  if (slots.any((u) => u != null && u.isNotEmpty)) {
    return productGalleryVitrineUrlsFromSlots(slots);
  }
  return productGalleryImageUrlsLegacy(row);
}

List<String?> productGallerySlotsToRpcJson(List<String?> slots) {
  final normalized = List<String?>.filled(kProductGallerySlotCount, null);
  for (var i = 0; i < kProductGallerySlotCount; i++) {
    final url = i < slots.length ? slots[i]?.trim() : null;
    normalized[i] = (url != null && url.isNotEmpty) ? url : null;
  }
  return normalized;
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