import '../../../../core/l10n/localized_text.dart';
import '../../../../shared/models/product_item.dart';
import '../models/catalog_constants.dart';

double? _parseSizeToken(String raw) {
  final normalized = raw.trim().replaceAll(',', '.');
  if (normalized.isEmpty) return null;
  return double.tryParse(normalized);
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

    return matchesCategory &&
        matchesSearch &&
        matchesMetal &&
        matchesInsert &&
        matchesSize;
  }).toList();
}
