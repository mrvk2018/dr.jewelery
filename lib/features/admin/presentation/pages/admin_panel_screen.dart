import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/l10n/app_locale_codes.dart';
import '../../../profile/domain/models/user_profile.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/product_item.dart';
import '../../../../shared/providers/catalog_scope.dart';
import '../../../profile/domain/models/order_item.dart';

/// Executive Dashboard (read-only): заказы и каталог из Supabase.
class AdminPanelScreen extends StatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  List<OrderItem> _orders = const [];
  bool _ordersLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAdminOrders();
      CatalogScope.of(context).refreshAdminBrowse();
    });
  }

  Future<void> _loadAdminOrders() async {
    if (!mounted) return;
    setState(() => _ordersLoading = true);
    try {
      final database = CatalogScope.of(context).database;
      final loaded = await database.getAllOrders(UserRole.admin);
      if (!mounted) return;
      setState(() {
        _orders = loaded;
        _ordersLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _ordersLoading = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = CatalogScope.of(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Панель управления',
          style: AppTypography.heading(fontSize: 20),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textSecondary,
          indicatorColor: AppColors.accent,
          tabs: const [
            Tab(text: 'Заказы'),
            Tab(text: 'Товары'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _OrdersTab(
            orders: _orders,
            loading: _ordersLoading,
            onRefresh: _loadAdminOrders,
          ),
          AnimatedBuilder(
            animation: catalog,
            builder: (context, _) {
              return _ProductsTab(
                products: catalog.adminProducts,
                hasMore: catalog.adminHasMore,
                isLoading: catalog.adminIsLoading,
                onLoadMore: catalog.loadNextAdminPage,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _OrdersTab extends StatelessWidget {
  const _OrdersTab({
    required this.orders,
    required this.loading,
    required this.onRefresh,
  });

  final List<OrderItem> orders;
  final bool loading;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (loading && orders.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (orders.isEmpty) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            Center(child: Text('Заказов пока нет')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: orders.length,
        separatorBuilder: (context, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final order = orders[index];
          return _AdminOrderCard(order: order);
        },
      ),
    );
  }
}

class _AdminOrderCard extends StatelessWidget {
  const _AdminOrderCard({required this.order});

  final OrderItem order;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  order.id,
                  style: AppTypography.caption(fontWeight: FontWeight.w700)
                      .copyWith(fontSize: 13),
                ),
              ),
              Text(
                order.status.label,
                style: AppTypography.caption(fontWeight: FontWeight.w600)
                    .copyWith(fontSize: 13, color: AppColors.accent),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(order.productName, style: AppTypography.productName()),
          const SizedBox(height: 6),
          Text(
            'Клиент: ${order.customerName}',
            style: AppTypography.productMeta(),
          ),
          if (order.hasSellerAttribution) ...[
            const SizedBox(height: 6),
            Text(
              'Продавец: ${order.sellerAttributionLabel}',
              style: AppTypography.productMeta().copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(order.dateLabel, style: AppTypography.productMeta()),
              Text(
                formatWon(order.amount),
                style: AppTypography.price(
                  fontSize: 14,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          if (order.hasShippingAddress) ...[
            const SizedBox(height: 12),
            Text(
              'Доставка (KR)',
              style: AppTypography.caption(fontWeight: FontWeight.w700)
                  .copyWith(fontSize: 13),
            ),
            const SizedBox(height: 6),
            Text(
              order.formattedShippingAddressKr,
              style: AppTypography.productMeta().copyWith(height: 1.45),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(text: order.formattedShippingAddressKr),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Адрес скопирован'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Скопировать адрес'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.accent,
                  side: const BorderSide(color: AppColors.accent),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProductsTab extends StatefulWidget {
  const _ProductsTab({
    required this.products,
    required this.hasMore,
    required this.isLoading,
    required this.onLoadMore,
  });

  final List<ProductItem> products;
  final bool hasMore;
  final bool isLoading;
  final VoidCallback onLoadMore;

  @override
  State<_ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<_ProductsTab> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.maxScrollExtent <= 0) return;
    if (position.pixels >= position.maxScrollExtent * 0.8) {
      widget.onLoadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading && widget.products.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: widget.products.length + 1 + (widget.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == 0) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Каталог (${widget.products.length}${widget.hasMore ? '+' : ''})',
                style: AppTypography.heading(fontSize: 20),
              ),
              const SizedBox(height: 12),
            ],
          );
        }

        final productIndex = index - 1;
        if (productIndex >= widget.products.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final product = widget.products[productIndex];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardBackground,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.nameTranslations[AppLocaleCodes.ru] ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.productName(),
                ),
                const SizedBox(height: 4),
                Text(
                  '${product.category} · ${formatWon(product.salePrice)} · -${product.discountPercent}%',
                  style: AppTypography.productMeta(),
                ),
                for (final code in const [
                  AppLocaleCodes.kk,
                  AppLocaleCodes.ko,
                  AppLocaleCodes.en,
                  AppLocaleCodes.uz,
                ])
                  if ((product.nameTranslations[code] ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${code.toUpperCase()}: ${product.nameTranslations[code]}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.productMeta(),
                      ),
                    ),
              ],
            ),
          ),
        );
      },
    );
  }
}
