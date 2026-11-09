import '../models/catalog_constants.dart';

/// ILIKE по `products.category` для UI-чипсов (склад: ед. число, синонимы).
List<String> categoryToIlikePatterns(Set<String> categories) {
  if (categories.isEmpty) return const [];

  final patterns = <String>{};
  for (final category in categories) {
    switch (category) {
      case CatalogCategories.rings:
        patterns.add('%Кольц%');
      case CatalogCategories.earrings:
        patterns.add('%Серьг%');
      case CatalogCategories.pendants:
        patterns.add('%Подвес%');
      case CatalogCategories.bracelets:
        patterns.add('%Браслет%');
      case CatalogCategories.watches:
        patterns.add('%Час%');
      case 'Цепи':
        patterns.add('%Цеп%');
      default:
        if (category.trim().isNotEmpty) {
          patterns.add('%${category.trim()}%');
        }
    }
  }
  return patterns.toList();
}

/// ILIKE по `products.metal` для семейства (Золото / Серебро / Платина).
List<String> metalFamilyToIlikePatterns(Set<String> families) {
  if (families.isEmpty) return const [];

  final patterns = <String>{};
  for (final family in families) {
    switch (family) {
      case CatalogMetalFamilies.gold:
        patterns.addAll(['%Au%', '%au%', '%золот%', '%gold%', '%585%', '%750%']);
      case CatalogMetalFamilies.platinum:
        patterns.addAll(['%платин%', '%platinum%', '%Pt%', '%pt%']);
      case CatalogMetalFamilies.silver:
        patterns.addAll(['%Серебр%', '%серебр%', '%Ag%', '%ag%', '%925%', '%silver%']);
    }
  }
  return patterns.toList();
}

/// ILIKE для точных чипсов металла (склад: Au585, 14K, а не UI-лейбл).
List<String> catalogMetalsToIlikePatterns(Set<String> metals) {
  if (metals.isEmpty) return const [];

  final patterns = <String>{};
  for (final metal in metals) {
    switch (metal) {
      case CatalogMetals.redGold:
        patterns.addAll(['%красн%', '%красное%', '%Au%', '%au%', '%золот%']);
      case CatalogMetals.whiteGold:
        patterns.addAll(['%бел%', '%white%', '%Au%', '%au%', '%золот%']);
      case CatalogMetals.silver:
        patterns.addAll(['%Серебр%', '%серебр%', '%Ag%', '%ag%', '%925%', '%silver%']);
      case CatalogMetals.platinum:
        patterns.addAll(['%платин%', '%platinum%', '%Pt%', '%pt%']);
      default:
        if (metal.trim().isNotEmpty) {
          patterns.add('%${metal.trim()}%');
        }
    }
  }
  return patterns.toList();
}

/// Семейство + точные чипсы → один OR-блок `metal.ilike` в PostgREST.
List<String> buildBrowseMetalIlikePatterns({
  required Set<String> families,
  required Set<String> exactMetals,
}) {
  return {
    ...metalFamilyToIlikePatterns(families),
    ...catalogMetalsToIlikePatterns(exactMetals),
  }.toList();
}
