import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/product_item.dart';
import '../../../../shared/providers/catalog_scope.dart';
import '../../domain/models/catalog_constants.dart';
import '../../domain/utils/catalog_filter_utils.dart';
import '../widgets/catalog_category_chips.dart';
import '../widgets/catalog_filter_drawer.dart';
import '../widgets/catalog_product_grid.dart';
import '../widgets/catalog_search_bar.dart';

/// Экран каталога с поиском, категориями и фильтрами.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final _searchController = TextEditingController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  String _searchQuery = '';
  String? _selectedCategory;
  CatalogFilterState _appliedFilters = const CatalogFilterState();
  CatalogFilterState _draftFilters = const CatalogFilterState();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ProductItem> get _allProducts => CatalogScope.of(context).products;

  List<ProductItem> get _filteredProducts => filterCatalogProducts(
        products: _allProducts,
        searchQuery: _searchQuery,
        category: _selectedCategory,
        filters: _appliedFilters,
      );

  List<ProductItem> get _draftFilteredProducts => filterCatalogProducts(
        products: _allProducts,
        searchQuery: _searchQuery,
        category: _selectedCategory,
        filters: _draftFilters,
      );

  void _openFilters() {
    setState(() => _draftFilters = _appliedFilters);
    _scaffoldKey.currentState?.openEndDrawer();
  }

  void _applyFilters() {
    setState(() => _appliedFilters = _draftFilters);
    Navigator.of(context).pop();
  }

  void _resetFilters() {
    setState(() {
      _draftFilters = const CatalogFilterState();
      _appliedFilters = const CatalogFilterState();
    });
  }

  @override
  Widget build(BuildContext context) {
    final catalog = CatalogScope.of(context);

    return AnimatedBuilder(
      animation: catalog,
      builder: (context, _) {
        final products = _filteredProducts;

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: AppColors.background,
          endDrawer: CatalogFilterDrawer(
            draftFilters: _draftFilters,
            resultCount: _draftFilteredProducts.length,
            onDraftChanged: (filters) {
              setState(() => _draftFilters = filters);
            },
            onApply: _applyFilters,
            onReset: _resetFilters,
          ),
          body: SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      'Каталог',
                      style: AppTypography.heading(fontSize: 24),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: CatalogSearchBar(
                    controller: _searchController,
                    activeFilterCount: _appliedFilters.activeCount,
                    onFilterTap: _openFilters,
                    onChanged: (value) {
                      setState(() => _searchQuery = value);
                    },
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                SliverToBoxAdapter(
                  child: CatalogCategoryChips(
                    selectedCategory: _selectedCategory,
                    onCategorySelected: (category) {
                      setState(() => _selectedCategory = category);
                    },
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: Text(
                      _selectedCategory == null
                          ? 'Все изделия · ${products.length}'
                          : '$_selectedCategory · ${products.length}',
                      style: AppTypography.caption(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ).copyWith(fontSize: 13),
                    ),
                  ),
                ),
                CatalogProductGrid(products: products),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
        );
      },
    );
  }
}
