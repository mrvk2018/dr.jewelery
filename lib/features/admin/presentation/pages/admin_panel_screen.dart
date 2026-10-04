import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/l10n/app_locale_codes.dart';
import '../../../../core/services/database_service.dart';
import '../../../profile/domain/models/user_profile.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/feedback_item.dart';
import '../../../../shared/models/product_item.dart';
import '../../../../shared/providers/catalog_scope.dart';
import '../../../../shared/providers/feedback_scope.dart';
import '../../../catalog/domain/models/catalog_constants.dart';
import '../../../profile/domain/models/order_item.dart';
import '../widgets/admin_marketing_section.dart';
import '../widgets/admin_sellers_section.dart';
import '../widgets/admin_product_form.dart';
/// Админ-панель владельца: заказы, товары и обратная связь.
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

  String _selectedCategory = CatalogCategories.rings;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAdminOrders());
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

  Future<void> _onAdminOrderStatusChanged(String orderId, String newStatus) async {
    final database = CatalogScope.of(context).database;
    try {
      await database.updateOrderStatus(orderId, newStatus, UserRole.admin);
      if (!mounted) return;
      setState(() {
        _orders = _orders
            .map(
              (order) => order.id == orderId
                  ? order.copyWith(
                      status: OrderStatus.fromSupabaseStatus(newStatus),
                    )
                  : order,
            )
            .toList();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось обновить статус: $e')),
      );
    }
  }
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _addProduct(ProductItem item) {
    CatalogScope.of(context).addProduct(item);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Товар успешно добавлен на витрину!',
          style: AppTypography.caption(
            color: AppColors.textOnPrimary,
            fontWeight: FontWeight.w600,
          ).copyWith(fontSize: 14),
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _deleteProduct(String id) {
    CatalogScope.of(context).removeProduct(id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Товар удалён',
          style: AppTypography.caption(
            color: AppColors.textOnPrimary,
            fontWeight: FontWeight.w600,
          ).copyWith(fontSize: 14),
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
  static const _catalogSyncTaskId = 'catalog_sync';
  static const _syncPollInterval = Duration(seconds: 3);
  /// Полный импорт с фото/переводами может занимать несколько минут.
  static const _syncPollMaxAttempts = 60;

  Future<bool> _isCatalogSyncTaskComplete() async {
    final row = await Supabase.instance.client
        .from('sync_tasks')
        .select('sync_requested')
        .eq('id', _catalogSyncTaskId)
        .maybeSingle();
    if (row == null) return false;
    final requested = row['sync_requested'];
    if (requested is bool) return !requested;
    return false;
  }

  Future<void> _waitForWarehouseSyncImport(BuildContext context) async {
    for (var attempt = 0; attempt < _syncPollMaxAttempts; attempt++) {
      await Future<void>.delayed(_syncPollInterval);
      if (!context.mounted) return;

      try {
        if (await _isCatalogSyncTaskComplete()) {
          if (!context.mounted) return;
          await CatalogScope.of(context).load();
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Данные успешно импортированы со склада! Каталог обновлен.',
              ),
            ),
          );
          return;
        }
      } catch (_) {
        // RLS/сеть — повторяем опрос до лимита попыток.
      }
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Импорт ещё не завершён (sync_requested=true). '
          'Убедитесь, что на ПК склада запущен cron «npm run sync», '
          'и проверьте логи sync.js (MSSQL connect/query timeout).',
        ),
      ),
    );
  }

  Future<void> _triggerSyncCatalog(BuildContext context) async {
    try {
      await Supabase.instance.client.functions.invoke('sync-catalog');

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Запрос на синхронизацию отправлен на склад. Пожалуйста, подождите...',
          ),
        ),
      );

      await _waitForWarehouseSyncImport(context);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка синхронизации: $e')),
        );
      }
    }
  }

  void _deleteFeedbackMessage(String id) {
    FeedbackScope.of(context).removeMessage(id);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Сообщение удалено',
          style: AppTypography.caption(
            color: AppColors.textOnPrimary,
            fontWeight: FontWeight.w600,
          ).copyWith(fontSize: 14),
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final catalog = CatalogScope.of(context);
    final feedback = FeedbackScope.of(context);

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
            Tab(text: 'Обратная связь'),
            Tab(text: 'Продавцы'),
            Tab(text: 'Маркетинг'),
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
            onStatusChanged: _onAdminOrderStatusChanged,
          ),
          AnimatedBuilder(
            animation: catalog,
            builder: (context, _) {
              return _ProductsTab(
                products: catalog.products,
                database: catalog.database,
                selectedCategory: _selectedCategory,
                onCategoryChanged: (value) {
                  setState(() => _selectedCategory = value);
                },
                onAddProduct: _addProduct,
                onDeleteProduct: _deleteProduct,
                onSyncCatalog: () => _triggerSyncCatalog(context),
              );
            },
          ),
          AnimatedBuilder(
            animation: feedback,
            builder: (context, _) {
              return _FeedbackTab(
                messages: feedback.messages,
                onDelete: _deleteFeedbackMessage,
              );
            },
          ),
          AdminSellersSection(database: catalog.database),
          AdminMarketingSection(database: catalog.database),
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
    required this.onStatusChanged,
  });

  final List<OrderItem> orders;
  final bool loading;
  final Future<void> Function() onRefresh;
  final Future<void> Function(String orderId, String newStatus) onStatusChanged;

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
          return _AdminOrderCard(
            order: order,
            onStatusChanged: (status) => onStatusChanged(order.id, status),
          );
        },
      ),
    );
  }
}

class _AdminOrderCard extends StatelessWidget {
  const _AdminOrderCard({
    required this.order,
    required this.onStatusChanged,
  });

  final OrderItem order;
  final ValueChanged<String> onStatusChanged;

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
              _AdminOrderStatusDropdown(
                value: order.adminStatusDropdownValue,
                onChanged: onStatusChanged,
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

class _AdminOrderStatusDropdown extends StatelessWidget {
  const _AdminOrderStatusDropdown({
    required this.value,
    required this.onChanged,
  });

  final String value;
  final ValueChanged<String> onChanged;

  static const _labels = {
    'paid': 'Оплачен',
    'in_transit': 'В пути',
    'delivered': 'Доставлен',
  };

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: value,
      underline: const SizedBox.shrink(),
      borderRadius: BorderRadius.circular(8),
      items: OrderItem.adminFulfillmentStatuses
          .map(
            (status) => DropdownMenuItem<String>(
              value: status,
              child: Text(_labels[status] ?? status),
            ),
          )
          .toList(),
      onChanged: (next) {
        if (next != null && next != value) onChanged(next);
      },
    );
  }
}

class _ProductsTab extends StatelessWidget {
  const _ProductsTab({
    required this.products,
    required this.selectedCategory,
    required this.database,
    required this.onCategoryChanged,
    required this.onAddProduct,
    required this.onDeleteProduct,
    required this.onSyncCatalog,
  });

  final List<ProductItem> products;
  final String selectedCategory;
  final DatabaseService database;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<ProductItem> onAddProduct;
  final ValueChanged<String> onDeleteProduct;
  final VoidCallback onSyncCatalog;
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Material(
          color: Colors.green.shade600,
          elevation: 3,
          shadowColor: Colors.green.shade900.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onSyncCatalog,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.sync_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Синхронизировать базу товаров',
                          style: AppTypography.productName().copyWith(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Нажмите на зелёную кнопку — импорт изделий и фото со склада',
                          style: AppTypography.productMeta().copyWith(
                            color: Colors.white.withValues(alpha: 0.92),
                            fontSize: 14,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.touch_app_rounded,
                    color: Colors.white.withValues(alpha: 0.85),
                    size: 28,
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        AdminProductForm(
          database: database,
          selectedCategory: selectedCategory,
          onCategoryChanged: onCategoryChanged,
          onSubmit: onAddProduct,
        ),
        const SizedBox(height: 24),
        Text(
          'Текущие товары (${products.length})',
          style: AppTypography.heading(fontSize: 20),
        ),
        const SizedBox(height: 12),
        ...products.map(
          (product) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  Expanded(
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
                  IconButton(
                    onPressed: () => onDeleteProduct(product.id),
                    icon: const Icon(Icons.delete_outline_rounded),
                    color: AppColors.saleRed,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FeedbackTab extends StatelessWidget {
  const _FeedbackTab({
    required this.messages,
    required this.onDelete,
  });

  final List<FeedbackItem> messages;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.inbox_outlined,
                size: 56,
                color: AppColors.textSecondary.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 16),
              Text(
                'Сообщений пока нет',
                style: AppTypography.heading(fontSize: 20),
              ),
              const SizedBox(height: 8),
              Text(
                'Здесь появятся благодарности, вопросы и жалобы клиентов',
                textAlign: TextAlign.center,
                style: AppTypography.productMeta().copyWith(fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: messages.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final message = messages[index];
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _LanguageBadge(languageCode: message.languageCode),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      message.formattedDateTime,
                      style: AppTypography.productMeta().copyWith(fontSize: 12),
                    ),
                  ),
                  IconButton(
                    onPressed: () => onDelete(message.id),
                    icon: const Icon(Icons.delete_outline_rounded),
                    color: AppColors.saleRed,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                message.message,
                style: AppTypography.productMeta().copyWith(
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _LanguageBadge extends StatelessWidget {
  const _LanguageBadge({required this.languageCode});

  final String languageCode;

  (Color background, Color foreground) get _colors {
    return switch (languageCode) {
      'ru' => (AppColors.accent.withValues(alpha: 0.18), AppColors.primary),
      'ko' => (const Color(0xFF0046FF).withValues(alpha: 0.15), const Color(0xFF0046FF)),
      'en' => (AppColors.textSecondary.withValues(alpha: 0.15), AppColors.textSecondary),
      'kk' => (const Color(0xFF00AFCA).withValues(alpha: 0.18), const Color(0xFF00AFCA)),
      'uz' => (const Color(0xFF009178).withValues(alpha: 0.15), const Color(0xFF009178)),
      _ => (AppColors.border.withValues(alpha: 0.5), AppColors.textPrimary),
    };
  }

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = _colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        languageCode.toUpperCase(),
        style: AppTypography.caption(
          color: foreground,
          fontWeight: FontWeight.w800,
        ).copyWith(fontSize: 11, letterSpacing: 0.5),
      ),
    );
  }
}
