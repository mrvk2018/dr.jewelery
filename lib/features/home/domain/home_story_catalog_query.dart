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
          categoryIlikePatterns: ['%Кольц%'],
        );
      case 'new':
        return const HomeStoryCatalogQuery(orderIdDescending: true);
      case 'earrings':
        return const HomeStoryCatalogQuery(
          categoryIlikePatterns: ['%Серьг%'],
        );
      case 'chains':
        return const HomeStoryCatalogQuery(
          categoryIlikePatterns: ['%Цеп%', '%Chain%'],
        );
      case 'gold':
        return const HomeStoryCatalogQuery(
          metalIlikePatterns: ['%Au%', '%золот%', '%gold%', '%585%', '%750%'],
        );
      case 'silver':
        return const HomeStoryCatalogQuery(
          metalIlikePatterns: [
            '%Серебр%',
            '%серебр%',
            '%Ag%',
            '%925%',
            '%silver%',
          ],
        );
      case 'gifts':
        return const HomeStoryCatalogQuery(searchQuery: 'подар');
      case 'all':
      default:
        return const HomeStoryCatalogQuery();
    }
  }
}
