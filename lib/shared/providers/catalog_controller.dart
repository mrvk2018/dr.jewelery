import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/services/database_service.dart';
import '../../features/catalog/domain/models/catalog_constants.dart';
import '../../features/catalog/domain/utils/catalog_metal_facet_utils.dart';
import '../../features/catalog/domain/utils/catalog_server_filter_utils.dart';
import '../../features/home/domain/home_story_catalog_query.dart';
import '../models/product_item.dart';

/// Глобальное состояние каталога: browse (paged) + home feed + admin list.
class CatalogController extends ChangeNotifier {
  CatalogController(this._database);

  static const int pageSize = 40;
  static const Duration searchDebounce = Duration(milliseconds: 350);

  final DatabaseService _database;
  DatabaseService get database => _database;

  final List<ProductItem> _products = [];
  final List<ProductItem> _homeProducts = [];
  final List<ProductItem> _adminProducts = [];

  final Set<String> _selectedCategories = {};
  final Set<String> _selectedMetals = {};
  final Set<String> _selectedSizes = {};
  final Set<String> _selectedInserts = {};

  String _searchQuery = '';
  String? _homeStoryFilterKey;

  int _offset = 0;
  bool _hasMore = true;
  bool _isLoading = false;
  bool _isLoadingMore = false;
  int _browseRequestGeneration = 0;
  Timer? _searchDebounceTimer;

  int _homeOffset = 0;
  bool _homeHasMore = true;
  bool _homeIsLoading = false;
  bool _homeIsLoadingMore = false;

  int _adminOffset = 0;
  bool _adminHasMore = true;
  bool _adminIsLoading = false;
  bool _adminIsLoadingMore = false;

  CatalogFilterState _clientBrowseFilters = const CatalogFilterState();

  String _desktopSkuSearch = '';
  Set<String> _serverMetalFamilies = {};
  Set<String> _serverFineness = {};

  List<ProductItem> get products => List.unmodifiable(_products);

  /// Покупательская витрина: только серверная выборка (без клиентской обрезки).
  List<ProductItem> get visibleBrowseProducts => List.unmodifiable(_products);

  List<ProductItem> get recommendedProducts => List.unmodifiable(_homeProducts);

  List<ProductItem> get adminProducts => List.unmodifiable(_adminProducts);

  Set<String> get selectedCategories => Set.unmodifiable(_selectedCategories);
  Set<String> get selectedMetals => Set.unmodifiable(_selectedMetals);
  Set<String> get selectedSizes => Set.unmodifiable(_selectedSizes);
  Set<String> get selectedInserts => Set.unmodifiable(_selectedInserts);

  String get searchQuery => _searchQuery;

  bool get hasMore => _hasMore;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;

  bool get homeHasMore => _homeHasMore;
  bool get homeIsLoading => _homeIsLoading;
  bool get homeIsLoadingMore => _homeIsLoadingMore;

  bool get adminHasMore => _adminHasMore;
  bool get adminIsLoading => _adminIsLoading;
  bool get adminIsLoadingMore => _adminIsLoadingMore;

  bool get _priceFilterActive =>
      _clientBrowseFilters.priceMinKrw >
          CatalogDesktopFilterBounds.priceMinKrw ||
      _clientBrowseFilters.priceMaxKrw <
          CatalogDesktopFilterBounds.priceMaxKrw;

  bool get _weightFilterActive =>
      _clientBrowseFilters.weightMinGrams >
          CatalogDesktopFilterBounds.weightMinGrams ||
      _clientBrowseFilters.weightMaxGrams <
          CatalogDesktopFilterBounds.weightMaxGrams;

  int get browseFilterActiveCount {
    var n = _selectedCategories.length +
        _selectedMetals.length +
        _selectedInserts.length +
        _selectedSizes.length;
    if (_searchQuery.isNotEmpty) n++;
    if (_priceFilterActive) n++;
    if (_weightFilterActive) n++;
    return n;
  }

  int get drawerFilterActiveCount => browseFilterActiveCount;

  int get desktopFilterActiveCount =>
      browseFilterActiveCount +
      _serverMetalFamilies.length +
      _serverFineness.length +
      (_desktopSkuSearch.isNotEmpty ? 1 : 0);

  CatalogFilterState get appliedDesktopFilters => CatalogFilterState(
        selectedMetals: Set<String>.from(_selectedMetals),
        selectedInserts: Set<String>.from(_selectedInserts),
        selectedSizes: _selectedSizes
            .map((s) => double.tryParse(s.replaceAll(',', '.')))
            .whereType<double>()
            .toSet(),
        selectedCategories: Set<String>.from(_selectedCategories),
        localSearchQuery: _desktopSkuSearch,
        priceMinKrw: _clientBrowseFilters.priceMinKrw,
        priceMaxKrw: _clientBrowseFilters.priceMaxKrw,
        weightMinGrams: _clientBrowseFilters.weightMinGrams,
        weightMaxGrams: _clientBrowseFilters.weightMaxGrams,
        selectedMetalFamilies: Set<String>.from(_serverMetalFamilies),
        selectedFineness: Set<String>.from(_serverFineness),
      );

  Set<String> get _browseMetalFacetLabels => {
        ..._selectedMetals,
        ..._serverMetalFamilies,
      };

  List<String> get _browseCategoryIlikePatterns =>
      categoryToIlikePatterns(_selectedCategories);

  List<String> get _browseMetalIlikePatterns =>
      metalFacetLabelsToIlikePatterns(_browseMetalFacetLabels);

  List<String> get _browseInsertIlikePatterns =>
      insertLabelsToIlikePatterns(_selectedInserts.toList());

  String? get homeStoryFilterKey => _homeStoryFilterKey;

  @override
  void dispose() {
    _searchDebounceTimer?.cancel();
    super.dispose();
  }

  Future<void> toggleHomeStoryFilter(String filterKey) async {
    if (filterKey == 'all') {
      _homeStoryFilterKey = null;
    } else if (_homeStoryFilterKey == filterKey) {
      _homeStoryFilterKey = null;
    } else {
      _homeStoryFilterKey = filterKey;
    }
    notifyListeners();
    await refreshHomeFeed();
  }

  Future<void> _fetchAdvancedPage({
    required int requestGeneration,
    required int offset,
    required void Function(List<ProductItem> page) onSuccess,
    String? searchQuery,
    List<String>? categories,
    List<String>? metals,
    List<String>? sizes,
    List<String>? inserts,
    int? minDiscountPercent,
    bool orderIdDescending = false,
    List<String> categoryIlikePatterns = const [],
    List<String> metalIlikePatterns = const [],
    List<String> insertIlikePatterns = const [],
    int? minSalePriceKrw,
    int? maxSalePriceKrw,
    double? minWeightGrams,
    double? maxWeightGrams,
    String? skuIlikeQuery,
    List<String>? finenessTokens,
  }) async {
    final page = await _database.getProductsAdvancedQuery(
      offset: offset,
      limit: pageSize,
      searchQuery: searchQuery,
      skuIlikeQuery: skuIlikeQuery,
      categories: categories,
      metals: metals,
      sizes: sizes,
      inserts: inserts,
      finenessTokens: finenessTokens,
      minDiscountPercent: minDiscountPercent,
      orderIdDescending: orderIdDescending,
      categoryIlikePatterns: categoryIlikePatterns,
      metalIlikePatterns: metalIlikePatterns,
      insertIlikePatterns: insertIlikePatterns,
      minSalePriceKrw: minSalePriceKrw,
      maxSalePriceKrw: maxSalePriceKrw,
      minWeightGrams: minWeightGrams,
      maxWeightGrams: maxWeightGrams,
    );
    if (requestGeneration != _browseRequestGeneration) return;
    onSuccess(page);
  }

  HomeStoryCatalogQuery get _activeHomeStoryQuery =>
      HomeStoryCatalogQuery.forStoryKey(_homeStoryFilterKey);

  /// Первая страница подборки главной (истории / «все»).
  Future<void> refreshHomeFeed() async {
    _homeIsLoading = true;
    _homeOffset = 0;
    _homeHasMore = true;
    notifyListeners();
    try {
      final query = _activeHomeStoryQuery;
      await _fetchAdvancedPage(
        requestGeneration: _browseRequestGeneration,
        offset: 0,
        searchQuery: query.searchQuery,
        categories: query.categories,
        metals: query.metals,
        minDiscountPercent: query.minDiscountPercent,
        orderIdDescending: query.orderIdDescending,
        categoryIlikePatterns: query.categoryIlikePatterns,
        metalIlikePatterns: query.metalIlikePatterns,
        onSuccess: (page) {
          _homeProducts
            ..clear()
            ..addAll(page);
          _homeOffset = page.length;
          _homeHasMore = page.length >= pageSize;
        },
      );
    } finally {
      _homeIsLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadNextHomePage() async {
    if (_homeIsLoading || _homeIsLoadingMore || !_homeHasMore) return;
    _homeIsLoadingMore = true;
    notifyListeners();
    try {
      final query = _activeHomeStoryQuery;
      await _fetchAdvancedPage(
        requestGeneration: _browseRequestGeneration,
        offset: _homeOffset,
        searchQuery: query.searchQuery,
        categories: query.categories,
        metals: query.metals,
        minDiscountPercent: query.minDiscountPercent,
        orderIdDescending: query.orderIdDescending,
        categoryIlikePatterns: query.categoryIlikePatterns,
        metalIlikePatterns: query.metalIlikePatterns,
        onSuccess: (page) {
          if (page.isEmpty) {
            _homeHasMore = false;
            return;
          }
          final existingIds = _homeProducts.map((p) => p.id).toSet();
          for (final item in page) {
            if (existingIds.add(item.id)) {
              _homeProducts.add(item);
            }
          }
          _homeOffset += page.length;
          if (page.length < pageSize) {
            _homeHasMore = false;
          }
        },
      );
    } finally {
      _homeIsLoadingMore = false;
      notifyListeners();
    }
  }

  CatalogFilterState get appliedDrawerFilters => CatalogFilterState(
        selectedMetals: Set<String>.from(_selectedMetals),
        selectedInserts: Set<String>.from(_selectedInserts),
        selectedSizes: _selectedSizes
            .map((s) => double.tryParse(s.replaceAll(',', '.')))
            .whereType<double>()
            .toSet(),
        priceMinKrw: _clientBrowseFilters.priceMinKrw,
        priceMaxKrw: _clientBrowseFilters.priceMaxKrw,
      );

  void applyDrawerFilters(CatalogFilterState state) {
    _selectedMetals
      ..clear()
      ..addAll(state.selectedMetals);
    _selectedInserts
      ..clear()
      ..addAll(state.selectedInserts);
    _selectedSizes
      ..clear()
      ..addAll(state.sizeTokens);
    _clientBrowseFilters = _clientBrowseFilters.copyWith(
      priceMinKrw: state.priceMinKrw,
      priceMaxKrw: state.priceMaxKrw,
    );
    unawaited(refreshBrowse());
  }

  void resetDrawerFilters() {
    _selectedMetals.clear();
    _selectedInserts.clear();
    _selectedSizes.clear();
    _clientBrowseFilters = _clientBrowseFilters.copyWith(
      priceMinKrw: CatalogDesktopFilterBounds.priceMinKrw,
      priceMaxKrw: CatalogDesktopFilterBounds.priceMaxKrw,
    );
    unawaited(refreshBrowse());
  }

  void resetAllBrowseFilters() {
    _selectedCategories.clear();
    _selectedMetals.clear();
    _selectedInserts.clear();
    _selectedSizes.clear();
    _searchQuery = '';
    _desktopSkuSearch = '';
    _serverMetalFamilies = {};
    _serverFineness = {};
    _clientBrowseFilters = const CatalogFilterState();
    _searchDebounceTimer?.cancel();
    notifyListeners();
    unawaited(refreshBrowse());
  }

  /// Синхронизация UI поиска при возврате на вкладку каталога.
  void pingBrowseUiSync() => notifyListeners();

  /// Обновление черновика слайдеров цены/веса (desktop) до «Применить».
  void setClientBrowseFilters(CatalogFilterState state) {
    _clientBrowseFilters = state.clientBrowseSlice;
    notifyListeners();
  }

  void applyDesktopSidebarFilters(CatalogFilterState state) {
    _selectedCategories
      ..clear()
      ..addAll(state.selectedCategories);
    _selectedMetals
      ..clear()
      ..addAll(state.selectedMetals);
    _desktopSkuSearch = state.localSearchQuery.trim();
    _serverMetalFamilies = Set<String>.from(state.selectedMetalFamilies);
    _serverFineness = Set<String>.from(state.selectedFineness);
    _clientBrowseFilters = state.clientBrowseSlice;
    notifyListeners();
    _selectedInserts.clear();
    _selectedSizes.clear();
    _searchQuery = '';
    unawaited(refreshBrowse());
  }

  void resetDesktopSidebarFilters() {
    resetAllBrowseFilters();
  }

  void toggleCategoryFilter(String category) {
    if (_selectedCategories.contains(category)) {
      _selectedCategories.remove(category);
    } else {
      _selectedCategories.add(category);
    }
    unawaited(refreshBrowse());
  }

  void toggleMetalFilter(String metal) {
    final next = toggleCatalogMetalFacet(_selectedMetals, metal);
    _selectedMetals
      ..clear()
      ..addAll(next);
    unawaited(refreshBrowse());
  }

  void toggleSizeFilter(String sizeToken) {
    if (_selectedSizes.contains(sizeToken)) {
      _selectedSizes.remove(sizeToken);
    } else {
      _selectedSizes.add(sizeToken);
    }
    unawaited(refreshBrowse());
  }

  void setSearchQuery(String query) {
    _searchDebounceTimer?.cancel();
    _searchDebounceTimer = Timer(searchDebounce, () {
      final normalized = query.trim();
      if (normalized == _searchQuery) return;
      _searchQuery = normalized;
      unawaited(refreshBrowse());
    });
  }

  void syncSearchQueryFromField(String query) {
    final normalized = query.trim();
    if (normalized == _searchQuery) return;
    _searchDebounceTimer?.cancel();
    _searchQuery = normalized;
    unawaited(refreshBrowse());
  }

  Future<void> load() => refreshBrowse();

  Future<void> refreshBrowse() async {
    final generation = ++_browseRequestGeneration;
    _isLoading = true;
    _offset = 0;
    _hasMore = true;
    notifyListeners();
    try {
      await _fetchAdvancedPage(
        requestGeneration: generation,
        offset: 0,
        searchQuery:
            _desktopSkuSearch.isNotEmpty ? null : (_searchQuery.isEmpty ? null : _searchQuery),
        skuIlikeQuery: _desktopSkuSearch.isEmpty ? null : _desktopSkuSearch,
        sizes: _selectedSizes.isEmpty ? null : _selectedSizes.toList(),
        finenessTokens:
            _serverFineness.isEmpty ? null : _serverFineness.toList(),
        categoryIlikePatterns: _browseCategoryIlikePatterns,
        metalIlikePatterns: _browseMetalIlikePatterns,
        insertIlikePatterns: _browseInsertIlikePatterns,
        minSalePriceKrw: _clientBrowseFilters.priceMinKrw,
        maxSalePriceKrw: _clientBrowseFilters.priceMaxKrw,
        minWeightGrams: _clientBrowseFilters.weightMinGrams,
        maxWeightGrams: _clientBrowseFilters.weightMaxGrams,
        onSuccess: (page) {
          if (generation != _browseRequestGeneration) return;
          _products
            ..clear()
            ..addAll(page);
          _offset = page.length;
          _hasMore = page.length >= pageSize;
        },
      );
    } finally {
      if (generation == _browseRequestGeneration) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadNextPage() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;
    final generation = _browseRequestGeneration;
    _isLoadingMore = true;
    notifyListeners();
    try {
      await _fetchAdvancedPage(
        requestGeneration: generation,
        offset: _offset,
        searchQuery:
            _desktopSkuSearch.isNotEmpty ? null : (_searchQuery.isEmpty ? null : _searchQuery),
        skuIlikeQuery: _desktopSkuSearch.isEmpty ? null : _desktopSkuSearch,
        sizes: _selectedSizes.isEmpty ? null : _selectedSizes.toList(),
        finenessTokens:
            _serverFineness.isEmpty ? null : _serverFineness.toList(),
        categoryIlikePatterns: _browseCategoryIlikePatterns,
        metalIlikePatterns: _browseMetalIlikePatterns,
        insertIlikePatterns: _browseInsertIlikePatterns,
        minSalePriceKrw: _clientBrowseFilters.priceMinKrw,
        maxSalePriceKrw: _clientBrowseFilters.priceMaxKrw,
        minWeightGrams: _clientBrowseFilters.weightMinGrams,
        maxWeightGrams: _clientBrowseFilters.weightMaxGrams,
        onSuccess: (page) {
          if (generation != _browseRequestGeneration) return;
          if (page.isEmpty) {
            _hasMore = false;
            return;
          }
          final existingIds = _products.map((p) => p.id).toSet();
          for (final item in page) {
            if (existingIds.add(item.id)) {
              _products.add(item);
            }
          }
          _offset += page.length;
          if (page.length < pageSize) {
            _hasMore = false;
          }
        },
      );
    } finally {
      if (generation == _browseRequestGeneration) {
        _isLoadingMore = false;
        notifyListeners();
      }
    }
  }

  /// Первая страница списка товаров в админке (все статусы, paged).
  Future<void> refreshAdminBrowse() async {
    _adminIsLoading = true;
    _adminOffset = 0;
    _adminHasMore = true;
    notifyListeners();
    try {
      final page = await _database.getProductsAdminPagedQuery(
        offset: 0,
        limit: pageSize,
      );
      _adminProducts
        ..clear()
        ..addAll(page);
      _adminOffset = page.length;
      _adminHasMore = page.length >= pageSize;
    } finally {
      _adminIsLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadNextAdminPage() async {
    if (_adminIsLoading || _adminIsLoadingMore || !_adminHasMore) return;
    _adminIsLoadingMore = true;
    notifyListeners();
    try {
      final page = await _database.getProductsAdminPagedQuery(
        offset: _adminOffset,
        limit: pageSize,
      );
      if (page.isEmpty) {
        _adminHasMore = false;
        return;
      }
      final existingIds = _adminProducts.map((p) => p.id).toSet();
      for (final item in page) {
        if (existingIds.add(item.id)) {
          _adminProducts.add(item);
        }
      }
      _adminOffset += page.length;
      if (page.length < pageSize) {
        _adminHasMore = false;
      }
    } finally {
      _adminIsLoadingMore = false;
      notifyListeners();
    }
  }
}
