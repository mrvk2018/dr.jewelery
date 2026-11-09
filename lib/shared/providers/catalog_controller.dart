import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/services/database_service.dart';
import '../../features/catalog/domain/models/catalog_constants.dart';
import '../../features/catalog/domain/utils/catalog_filter_utils.dart';
import '../../features/catalog/domain/utils/catalog_server_filter_utils.dart';
import '../../features/home/domain/home_story_catalog_query.dart';
import '../models/product_item.dart';

/// Глобальное состояние каталога: browse (paged) + home feed + admin list.
class CatalogController extends ChangeNotifier {
  CatalogController(this._database);

  static const int pageSize = 40;

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

  int _homeOffset = 0;
  bool _homeHasMore = true;
  bool _homeIsLoading = false;
  bool _homeIsLoadingMore = false;

  int _adminOffset = 0;
  bool _adminHasMore = true;
  bool _adminIsLoading = false;
  bool _adminIsLoadingMore = false;

  CatalogFilterState _clientBrowseFilters = const CatalogFilterState();
  CatalogFilterState? _clientPreviewExtras;

  String _desktopSkuSearch = '';
  Set<String> _serverMetalFamilies = {};
  Set<String> _serverFineness = {};

  List<ProductItem> get products => List.unmodifiable(_products);

  /// Серверная выборка + клиент (цена/вес); до Apply — превью по загруженным строкам.
  List<ProductItem> get visibleBrowseProducts {
    final preview = _clientPreviewExtras;
    final merged = CatalogFilterState(
      priceMinKrw: _clientBrowseFilters.priceMinKrw,
      priceMaxKrw: _clientBrowseFilters.priceMaxKrw,
      weightMinGrams: _clientBrowseFilters.weightMinGrams,
      weightMaxGrams: _clientBrowseFilters.weightMaxGrams,
      localSearchQuery:
          preview != null ? preview.localSearchQuery : '',
      selectedMetalFamilies: preview != null
          ? preview.selectedMetalFamilies
          : const {},
      selectedFineness:
          preview != null ? preview.selectedFineness : const {},
    );
    return filterCatalogProducts(
      products: _products,
      filters: merged,
    );
  }

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

  int get drawerFilterActiveCount =>
      _selectedMetals.length + _selectedInserts.length + _selectedSizes.length;

  int get desktopFilterActiveCount =>
      drawerFilterActiveCount +
      _selectedCategories.length +
      _clientBrowseFilters.activeCount +
      (_desktopSkuSearch.isNotEmpty ? 1 : 0) +
      _serverMetalFamilies.length +
      _serverFineness.length;

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

  List<String> get _browseCategoryIlikePatterns =>
      categoryToIlikePatterns(_selectedCategories);

  List<String> get _browseMetalIlikePatterns => buildBrowseMetalIlikePatterns(
        families: _serverMetalFamilies,
        exactMetals: _selectedMetals,
      );

  String? get homeStoryFilterKey => _homeStoryFilterKey;

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
  }) async {
    final page = await _database.getProductsAdvancedQuery(
      offset: offset,
      limit: pageSize,
      searchQuery: searchQuery,
      categories: categories,
      metals: metals,
      sizes: sizes,
      inserts: inserts,
      minDiscountPercent: minDiscountPercent,
      orderIdDescending: orderIdDescending,
      categoryIlikePatterns: categoryIlikePatterns,
      metalIlikePatterns: metalIlikePatterns,
    );
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
    unawaited(refreshBrowse());
  }

  void resetDrawerFilters() {
    _selectedMetals.clear();
    _selectedInserts.clear();
    _selectedSizes.clear();
    unawaited(refreshBrowse());
  }

  /// Превью слайдеров (клиент) и draft chip-ов на загруженной выборке.
  void setClientBrowseFilters(CatalogFilterState state) {
    _clientBrowseFilters = state.clientBrowseSlice;
    _clientPreviewExtras = state.clientPreviewSlice;
    notifyListeners();
  }

  void applyDesktopSidebarFilters(CatalogFilterState state) {
    _selectedCategories
      ..clear()
      ..addAll(state.selectedCategories);
    _selectedMetals
      ..clear()
      ..addAll(state.selectedMetals);
    _selectedInserts
      ..clear()
      ..addAll(state.selectedInserts);
    _selectedSizes
      ..clear()
      ..addAll(state.sizeTokens);
    _desktopSkuSearch = state.localSearchQuery.trim();
    _serverMetalFamilies = Set<String>.from(state.selectedMetalFamilies);
    _serverFineness = Set<String>.from(state.selectedFineness);
    _clientBrowseFilters = state.clientBrowseSlice;
    _clientPreviewExtras = null;
    notifyListeners();
    unawaited(refreshBrowse());
  }

  void resetDesktopSidebarFilters() {
    _selectedCategories.clear();
    _selectedMetals.clear();
    _selectedInserts.clear();
    _selectedSizes.clear();
    _desktopSkuSearch = '';
    _serverMetalFamilies = {};
    _serverFineness = {};
    _clientBrowseFilters = const CatalogFilterState();
    _clientPreviewExtras = null;
    _searchQuery = '';
    unawaited(refreshBrowse());
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
    if (_selectedMetals.contains(metal)) {
      _selectedMetals.remove(metal);
    } else {
      _selectedMetals.add(metal);
    }
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
    final normalized = query.trim();
    if (normalized == _searchQuery) return;
    _searchQuery = normalized;
    unawaited(refreshBrowse());
  }

  Future<void> load() => refreshBrowse();

  Future<void> refreshBrowse() async {
    _isLoading = true;
    _offset = 0;
    _hasMore = true;
    notifyListeners();
    try {
      final page = await _database.getProductsAdvancedQuery(
        offset: 0,
        limit: pageSize,
        searchQuery:
            _desktopSkuSearch.isNotEmpty ? null : (_searchQuery.isEmpty ? null : _searchQuery),
        skuIlikeQuery:
            _desktopSkuSearch.isEmpty ? null : _desktopSkuSearch,
        sizes: _selectedSizes.isEmpty ? null : _selectedSizes.toList(),
        inserts: _selectedInserts.isEmpty ? null : _selectedInserts.toList(),
        finenessTokens:
            _serverFineness.isEmpty ? null : _serverFineness.toList(),
        categoryIlikePatterns: _browseCategoryIlikePatterns,
        metalIlikePatterns: _browseMetalIlikePatterns,
      );
      _products
        ..clear()
        ..addAll(page);
      _clientPreviewExtras = null;
      _offset = page.length;
      _hasMore = page.length >= pageSize;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadNextPage() async {
    if (_isLoading || _isLoadingMore || !_hasMore) return;
    _isLoadingMore = true;
    notifyListeners();
    try {
      final page = await _database.getProductsAdvancedQuery(
        offset: _offset,
        limit: pageSize,
        searchQuery:
            _desktopSkuSearch.isNotEmpty ? null : (_searchQuery.isEmpty ? null : _searchQuery),
        skuIlikeQuery:
            _desktopSkuSearch.isEmpty ? null : _desktopSkuSearch,
        sizes: _selectedSizes.isEmpty ? null : _selectedSizes.toList(),
        inserts: _selectedInserts.isEmpty ? null : _selectedInserts.toList(),
        finenessTokens:
            _serverFineness.isEmpty ? null : _serverFineness.toList(),
        categoryIlikePatterns: _browseCategoryIlikePatterns,
        metalIlikePatterns: _browseMetalIlikePatterns,
      );
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
    } finally {
      _isLoadingMore = false;
      notifyListeners();
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
