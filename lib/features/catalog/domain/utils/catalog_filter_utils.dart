import '../../../../core/l10n/localized_text.dart';
import '../../../../shared/models/product_item.dart';
import '../models/catalog_constants.dart';

/// Фильтрация демонстрационного каталога по категории, поиску и фильтрам.
List<ProductItem> filterCatalogProducts({
  required List<ProductItem> products,
  String searchQuery = '',
  String? category,
  CatalogFilterState filters = const CatalogFilterState(),
}) {
  final query = searchQuery.trim().toLowerCase();

  return products.where((product) {
    final matchesCategory =
        category == null || category.isEmpty || product.category == category;

    final matchesSearch = query.isEmpty ||
        LocalizedText.containsQuery(product.name, query) ||
        LocalizedText.containsQuery(product.description, query) ||
        product.metal.toLowerCase().contains(query) ||
        product.category.toLowerCase().contains(query);

    final matchesMetal = filters.selectedMetals.isEmpty ||
        filters.selectedMetals.contains(product.metal);

    final matchesInsert = filters.selectedInserts.isEmpty ||
        filters.selectedInserts.contains(product.insert);

    final matchesSize = filters.selectedSize == null ||
        product.availableSizes.isEmpty ||
        product.availableSizes.contains(filters.selectedSize);

    return matchesCategory &&
        matchesSearch &&
        matchesMetal &&
        matchesInsert &&
        matchesSize;
  }).toList();
}
