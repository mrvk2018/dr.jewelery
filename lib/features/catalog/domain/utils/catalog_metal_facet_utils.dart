import '../models/catalog_constants.dart';

/// Цветовые оттенки золота (взаимоисключение с чипом «Золото»).
const Set<String> catalogGoldColorMetalLabels = {
  CatalogMetals.redGold,
  CatalogMetals.yellowGold,
  CatalogMetals.whiteGold,
};

/// Переключение металлического фасета с взаимоисключением «Золото» ↔ оттенки.
Set<String> toggleCatalogMetalFacet(Set<String> selected, String label) {
  final updated = Set<String>.from(selected);
  if (updated.contains(label)) {
    updated.remove(label);
    return updated;
  }
  updated.add(label);
  if (label == CatalogMetals.gold) {
    updated.removeAll(catalogGoldColorMetalLabels);
  } else if (catalogGoldColorMetalLabels.contains(label)) {
    updated.remove(CatalogMetals.gold);
  }
  return updated;
}

/// ILIKE-шаблоны по `products.metal` / `metal_type` (аналог `showroom_metal_facet_match`).
List<String> metalFacetLabelsToIlikePatterns(Set<String> facetLabels) {
  if (facetLabels.isEmpty) return const [];

  final patterns = <String>{};
  for (final label in facetLabels) {
    switch (label) {
      case CatalogMetals.gold:
        patterns.addAll(['%золото%', '%585%', '%750%']);
      case CatalogMetals.redGold:
        patterns.add('%красн%');
      case CatalogMetals.yellowGold:
        patterns.addAll(['%жёлт%', '%желт%']);
      case CatalogMetals.whiteGold:
        patterns.add('%бел%');
      case CatalogMetals.silver:
        patterns.addAll(['%серебр%', '%925%']);
      case CatalogMetals.platinum:
        patterns.addAll(['%платин%', '%pt%']);
      default:
        final trimmed = label.trim();
        if (trimmed.isNotEmpty) {
          patterns.add('%$trimmed%');
        }
    }
  }
  return patterns.toList();
}

/// Подстроки для `products.insert` (чипы UI ≠ точные значения DrJaw).
List<String> insertLabelsToIlikePatterns(List<String> labels) {
  if (labels.isEmpty) return const [];

  final patterns = <String>{};
  for (final label in labels) {
    switch (label) {
      case CatalogInserts.diamond:
        patterns.add('%брил%');
      case CatalogInserts.emerald:
        patterns.add('%изумр%');
      case CatalogInserts.sapphire:
        patterns.add('%сапф%');
      case CatalogInserts.topaz:
        patterns.add('%топаз%');
      case CatalogInserts.none:
        patterns.addAll(['%—%', '%без%', '%нет%']);
      default:
        final trimmed = label.trim();
        if (trimmed.isNotEmpty) {
          patterns.add('%$trimmed%');
        }
    }
  }
  return patterns.toList();
}
