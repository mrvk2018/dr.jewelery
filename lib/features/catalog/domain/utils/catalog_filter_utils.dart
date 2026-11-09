import '../../../../core/l10n/localized_text.dart';
import '../../../../shared/models/product_item.dart';
import '../models/catalog_constants.dart';

double? _parseSizeToken(String raw) {
  final normalized = raw.trim().replaceAll(',', '.');
  if (normalized.isEmpty) return null;
  return double.tryParse(normalized);
}

bool _metalMatchesFamily(String metal, Set<String> families) {
  if (families.isEmpty) return true;
  final m = metal.toLowerCase();
  for (final family in families) {
    switch (family) {
      case CatalogMetalFamilies.gold:
        if (m.contains('золот') || m.contains('gold') || m.contains('au')) {
          return true;
        }
      case CatalogMetalFamilies.platinum:
        if (m.contains('платин') || m.contains('pt') || m.contains('plat')) {
          return true;
        }
      case CatalogMetalFamilies.silver:
        if (m.contains('серебр') || m.contains('silver') || m.contains('ag')) {
          return true;
        }
    }
  }
  return false;
}

bool _matchesFineness(ProductItem product, Set<String> finenessTokens) {
  if (finenessTokens.isEmpty) return true;
  final haystack =
      '${product.metal} ${product.sku}'.toLowerCase();
  return finenessTokens.any((token) => haystack.contains(token.toLowerCase()));
}

/// Faceted-фильтрация каталога (локальный fallback и превью drawer).
List<ProductItem> filterCatalogProducts({
  required List<ProductItem> products,
  String searchQuery = '',
  String? category,
  List<String>? categories,
  List<String>? metals,
  List<String>? sizes,
  List<String>? inserts,
  CatalogFilterState filters = const CatalogFilterState(),
  int? priceMinKrw,
  int? priceMaxKrw,
  double? weightMinGrams,
  double? weightMaxGrams,
}) {
  final query = searchQuery.trim().toLowerCase();
  final categorySet = {
    ...?categories?.map((c) => c.trim()).where((c) => c.isNotEmpty),
    if (category != null && category.isNotEmpty) category,
  };
  final metalSet = {
    ...?metals?.map((m) => m.trim()).where((m) => m.isNotEmpty),
    ...filters.selectedMetals,
  };
  final insertSet = {
    ...?inserts?.map((i) => i.trim()).where((i) => i.isNotEmpty),
    ...filters.selectedInserts,
  };
  final sizeTokens = {
    ...?sizes?.map((s) => s.trim()).where((s) => s.isNotEmpty),
    ...filters.selectedSizes.map((s) => s.toString()),
  };

  final effectivePriceMin =
      priceMinKrw ?? filters.priceMinKrw;
  final effectivePriceMax =
      priceMaxKrw ?? filters.priceMaxKrw;
  final effectiveWeightMin =
      weightMinGrams ?? filters.weightMinGrams;
  final effectiveWeightMax =
      weightMaxGrams ?? filters.weightMaxGrams;

  return products.where((product) {
    final matchesCategory = categorySet.isEmpty ||
        categorySet.contains(product.category);

    final matchesSearch = query.isEmpty ||
        LocalizedText.containsQuery(product.name, query) ||
        LocalizedText.containsQuery(product.description, query) ||
        product.sku.toLowerCase().contains(query) ||
        product.metal.toLowerCase().contains(query) ||
        product.category.toLowerCase().contains(query) ||
        product.insert.toLowerCase().contains(query);

    final matchesMetal =
        metalSet.isEmpty || metalSet.contains(product.metal);

    final matchesInsert =
        insertSet.isEmpty || insertSet.contains(product.insert);

    final matchesSize = sizeTokens.isEmpty ||
        product.availableSizes.isEmpty ||
        sizeTokens.any((token) {
          final parsed = _parseSizeToken(token);
          if (parsed == null) return false;
          return product.availableSizes.any(
            (size) => (size - parsed).abs() < 0.001,
          );
        });

    final matchesPrice = product.salePrice >= effectivePriceMin &&
        product.salePrice <= effectivePriceMax;

    final weight = product.weightGrams;
    final matchesWeight = weight == null ||
        (weight >= effectiveWeightMin && weight <= effectiveWeightMax);

    final matchesMetalFamily =
        _metalMatchesFamily(product.metal, filters.selectedMetalFamilies);

    final matchesFineness = _matchesFineness(product, filters.selectedFineness);

    return matchesCategory &&
        matchesSearch &&
        matchesMetal &&
        matchesInsert &&
        matchesSize &&
        matchesPrice &&
        matchesWeight &&
        matchesMetalFamily &&
        matchesFineness;
  }).toList();
}
