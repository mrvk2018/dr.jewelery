import 'package:flutter/material.dart';

import '../../../../core/l10n/app_locale_codes.dart';
import '../../../../core/services/database_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/feedback_item.dart';
import '../../../../shared/models/product_item.dart';
import '../../../../shared/providers/catalog_scope.dart';
import '../../../../shared/providers/feedback_scope.dart';
import '../../../catalog/domain/models/catalog_constants.dart';
import '../../../profile/domain/models/order_item.dart';
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
  late List<OrderItem> _orders;

  String _selectedCategory = CatalogCategories.rings;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _orders = List<OrderItem>.from(demoAdminOrders);
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
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _OrdersTab(orders: _orders),
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
        ],
      ),
    );
  }
}
class _OrdersTab extends StatelessWidget {
  const _OrdersTab({required this.orders});

  final List<OrderItem> orders;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: orders.length,
      separatorBuilder: (context, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final order = orders[index];
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
                  _AdminStatusBadge(status: order.status),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                order.productName,
                style: AppTypography.productName(),
              ),
              const SizedBox(height: 6),
              Text(
                'Клиент: ${order.customerName}',
                style: AppTypography.productMeta(),
              ),
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
            ],
          ),
        );
      },
    );
  }
}

class _AdminStatusBadge extends StatelessWidget {
  const _AdminStatusBadge({required this.status});

  final OrderStatus status;

  Color get _color {
    return switch (status) {
      OrderStatus.newOrder => AppColors.saleRed,
      OrderStatus.paid => AppColors.accent,
      OrderStatus.delivered => AppColors.textSecondary,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.label,
        style: AppTypography.caption(
          color: _color,
          fontWeight: FontWeight.w700,
        ).copyWith(fontSize: 11),
      ),
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
  });

  final List<ProductItem> products;
  final String selectedCategory;
  final DatabaseService database;
  final ValueChanged<String> onCategoryChanged;
  final ValueChanged<ProductItem> onAddProduct;
  final ValueChanged<String> onDeleteProduct;
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
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
