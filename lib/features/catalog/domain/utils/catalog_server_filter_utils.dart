import '../models/catalog_constants.dart';

// Карта построена по снимку Supabase (2026-03-24, status=active):
// metal: «585 красное», «Золото(585)», «Серебро(925)»
// category: «Кольцо», «Серьги», «Подвеска», «Браслет (женский)», «Цепь», … (21 значение)

/// ILIKE по `products.category` для UI-чипсов.
List<String> categoryToIlikePatterns(Set<String> categories) {
  if (categories.isEmpty) return const [];

  final patterns = <String>{};
  for (final category in categories) {
    switch (category) {
      case CatalogCategories.rings:
        patterns.addAll(['%Кольц%', '%Обручальное%']);
      case CatalogCategories.earrings:
        patterns.addAll(['%Серьг%', '%Пусcет%', '%Кафф%', '%Конго%']);
      case CatalogCategories.pendants:
        patterns.addAll(['%Подвес%', '%Крест%', '%Икона%']);
      case CatalogCategories.bracelets:
        patterns.addAll(['%Браслет%']);
      case CatalogCategories.watches:
        patterns.addAll(['%Час%']);
      case 'Цепи':
        patterns.addAll(['%Цеп%', '%Гайтан%']);
      default:
        if (category.trim().isNotEmpty) {
          patterns.add('%${category.trim()}%');
        }
    }
  }
  return patterns.toList();
}

/// ILIKE по `products.metal` — семейство (чип «Золото» / «Серебро» / «Платина»).
List<String> metalFamilyToIlikePatterns(Set<String> families) {
  if (families.isEmpty) return const [];

  final patterns = <String>{};
  for (final family in families) {
    switch (family) {
      case CatalogMetalFamilies.gold:
        // В БД нет Au/14K — только «Золото(585)» и «585 красное».
        patterns.addAll(['%золото%', '%585%', '%красн%']);
      case CatalogMetalFamilies.platinum:
        patterns.addAll(['%платин%', '%platinum%', '%Pt%', '%pt%']);
      case CatalogMetalFamilies.silver:
        patterns.addAll(['%серебр%', '%925%']);
    }
  }
  return patterns.toList();
}

/// ILIKE для точных чипсов металла (UI-лейблы ≠ значение колонки).
List<String> catalogMetalsToIlikePatterns(Set<String> metals) {
  if (metals.isEmpty) return const [];

  final patterns = <String>{};
  for (final metal in metals) {
    switch (metal) {
      case CatalogMetals.redGold:
        patterns.addAll(['%красн%', '%585%']);
      case CatalogMetals.whiteGold:
        patterns.addAll(['%золото%', '%бел%', '%585%']);
      case CatalogMetals.silver:
        patterns.addAll(['%серебр%', '%925%']);
      case CatalogMetals.platinum:
        patterns.addAll(['%платин%', '%pt%']);
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
