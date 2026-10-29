import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/providers/catalog_controller.dart';
import '../../../../shared/providers/catalog_scope.dart';
import '../../domain/models/catalog_constants.dart';
import '../widgets/catalog_category_chips.dart';
import '../widgets/catalog_filter_drawer.dart';
import '../widgets/catalog_product_grid.dart';
import '../widgets/catalog_search_bar.dart';

/// Экран каталога: server-side faceted search + infinite scroll.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  final _searchController = TextEditingController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _scrollController = ScrollController();

  CatalogFilterState _draftFilters = const CatalogFilterState();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final catalog = CatalogScope.of(context);
      if (catalog.products.isEmpty && !catalog.isLoading) {
        catalog.refreshBrowse();
      }
    });
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final catalog = CatalogScope.of(context);
    final position = _scrollController.position;
    if (position.maxScrollExtent <= 0) return;
    if (position.pixels >= position.maxScrollExtent * 0.8) {
      catalog.loadNextPage();
    }
  }

  void _openFilters() {
    final catalog = CatalogScope.of(context);
    setState(() => _draftFilters = catalog.appliedDrawerFilters);
    _scaffoldKey.currentState?.openEndDrawer();
  }

  void _applyFilters() {
    CatalogScope.of(context).applyDrawerFilters(_draftFilters);
    Navigator.of(context).pop();
  }

  void _resetFilters() {
    setState(() => _draftFilters = const CatalogFilterState());
    CatalogScope.of(context).resetDrawerFilters();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = CatalogScope.of(context);

    return AnimatedBuilder(
      animation: catalog,
      builder: (context, _) {
        final products = catalog.products;

        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: AppColors.background,
          endDrawer: CatalogFilterDrawer(
            draftFilters: _draftFilters,
            resultCount: products.length,
            onDraftChanged: (filters) {
              setState(() => _draftFilters = filters);
            },
            onApply: _applyFilters,
            onReset: _resetFilters,
          ),
          body: SafeArea(
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Text(
                      context.l10n.catalog,
                      style: AppTypography.heading(fontSize: 24),
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: CatalogSearchBar(
                    controller: _searchController,
                    activeFilterCount: catalog.drawerFilterActiveCount +
                        catalog.selectedCategories.length,
                    onFilterTap: _openFilters,
                    onChanged: catalog.setSearchQuery,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                SliverToBoxAdapter(
                  child: CatalogCategoryChips(
                    selectedCategories: catalog.selectedCategories,
                    onCategoryToggle: catalog.toggleCategoryFilter,
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    child: Text(
                      _buildSummaryLabel(catalog, products.length),
                      style: AppTypography.caption(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w500,
                      ).copyWith(fontSize: 13),
                    ),
                  ),
                ),
                if (catalog.isLoading && products.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  CatalogProductGrid(products: products),
                if (products.isNotEmpty && catalog.hasMore)
                  const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  ),
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              ],
            ),
          ),
        );
      },
    );
  }

  String _buildSummaryLabel(CatalogController catalog, int visibleCount) {
    if (catalog.isLoading && visibleCount == 0) {
      return 'Загрузка каталога…';
    }
    if (catalog.selectedCategories.isEmpty) {
      return 'Все изделия · $visibleCount${catalog.hasMore ? '+' : ''}';
    }
    final labels = catalog.selectedCategories.join(', ');
    return '$labels · $visibleCount${catalog.hasMore ? '+' : ''}';
  }
}
