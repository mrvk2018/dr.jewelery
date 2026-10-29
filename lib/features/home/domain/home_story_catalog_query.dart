import '../../catalog/domain/models/catalog_constants.dart';

/// Параметры серверного запроса подборки «Истории» на главной.
class HomeStoryCatalogQuery {
  const HomeStoryCatalogQuery({
    this.categories,
    this.metals,
    this.searchQuery,
    this.categoryIlikePatterns = const [],
    this.metalIlikePatterns = const [],
    this.minDiscountPercent,
    this.orderIdDescending = false,
  });

  final List<String>? categories;
  final List<String>? metals;
  final String? searchQuery;
  final List<String> categoryIlikePatterns;
  final List<String> metalIlikePatterns;
  final int? minDiscountPercent;
  final bool orderIdDescending;

  static HomeStoryCatalogQuery forStoryKey(String? filterKey) {
    switch (filterKey) {
      case 'discounts':
        return const HomeStoryCatalogQuery(minDiscountPercent: 1);
      case 'rings':
        return const HomeStoryCatalogQuery(
          categories: [CatalogCategories.rings],
        );
      case 'new':
        return const HomeStoryCatalogQuery(orderIdDescending: true);
      case 'earrings':
        return const HomeStoryCatalogQuery(
          categories: [CatalogCategories.earrings],
        );
      case 'chains':
        return const HomeStoryCatalogQuery(
          categoryIlikePatterns: ['%Цеп%', '%Chain%'],
        );
      case 'gold':
        return const HomeStoryCatalogQuery(
          metalIlikePatterns: ['%золото%', '%gold%'],
        );
      case 'silver':
        return const HomeStoryCatalogQuery(
          metalIlikePatterns: ['%серебро%', '%silver%'],
        );
      case 'gifts':
        return const HomeStoryCatalogQuery(searchQuery: 'подар');
      case 'all':
      default:
        return const HomeStoryCatalogQuery();
    }
  }
}
