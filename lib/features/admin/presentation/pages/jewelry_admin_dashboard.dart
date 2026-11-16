import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/admin/admin_access.dart';
import '../../../../core/constants/jewelry_category_subtypes.dart';
import '../../../../core/constants/jewelry_gem_inserts.dart';
import '../../../../core/widgets/jewelry_gem_insert_picker_dialog.dart';
import '../../../../core/services/database_service.dart';
import '../../../../shared/providers/profile_scope.dart';
import '../../application/pos_cart_controller.dart';
import '../widgets/admin_pos_cart_sheet.dart';
import '../../../../shared/models/product_item.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../catalog/presentation/widgets/smart_filter_widget.dart';
import '../../../printing/application/label_print_service.dart';
import '../../../printing/domain/jewelry_label_data.dart';
import '../../../printing/domain/jewelry_label_layout.dart';
import '../../../printing/infrastructure/browser_label_print.dart';
import '../../../printing/presentation/widgets/jewelry_label_preview.dart';
import '../../../printing/presentation/widgets/product_return_dialog.dart';
import '../../../../core/utils/product_gallery_urls.dart';
import '../../../../core/utils/store_location_utils.dart';
import '../../data/admin_manual_product_storage.dart';
import '../screens/draft_intake_screen.dart';

/// Склад/sync: камни в `insert`, legacy Pro — в `gem_inserts`.
String adminProductInsertLabel(Map<String, dynamic> row) {
  final gems = row['gem_inserts']?.toString().trim();
  if (gems != null && gems.isNotEmpty) return gems;
  final insert = row['insert']?.toString().trim();
  if (insert != null && insert.isNotEmpty) return insert;
  return '—';
}

/// Цена продажи для таблицы витрины (как бирка / POS / редактирование).
int? adminShowroomSalePriceKrw(Map<String, dynamic> row) {
  final raw = row['sale_price'] ?? row['price'];
  if (raw is num) {
    final value = raw.round();
    return value > 0 ? value : null;
  }
  if (raw == null) return null;
  final parsed = int.tryParse(raw.toString().replaceAll(RegExp(r'[^\d]'), ''));
  if (parsed == null || parsed <= 0) return null;
  return parsed;
}

String adminShowroomKrwLabel(int krw) {
  final spaced = krw.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]} ',
  );
  return '$spaced ₩';
}

String adminShowroomSalePriceLabel(Map<String, dynamic> row) {
  final krw = adminShowroomSalePriceKrw(row);
  if (krw == null) return '—';
  return adminShowroomKrwLabel(krw);
}

/// Наименование витрины из `products.name` (jsonb или строка).
String extractStoredProductName(Map<String, dynamic> row) {
  final raw = row['name'];
  if (raw is String) {
    final text = raw.trim();
    return text.isEmpty ? '—' : text;
  }
  if (raw is Map) {
    for (final key in ['ru', 'ko', 'en']) {
      final text = raw[key]?.toString().trim();
      if (text != null && text.isNotEmpty) return text;
    }
  }
  return '—';
}

/// Десктопный рабочий стол «Доктор Ювелир»: витрина + медиа + KPI.
class JewelryAdminDashboard extends StatefulWidget {
  JewelryAdminDashboard({
    super.key,
    DatabaseService? database,
    this.onPosSaleArchived,
  }) : database = database ?? DatabaseService.create();

  final DatabaseService database;
  final VoidCallback? onPosSaleArchived;

  @override
  State<JewelryAdminDashboard> createState() => _JewelryAdminDashboardState();
}

class _JewelryAdminDashboardState extends State<JewelryAdminDashboard> {
  final LabelPrintService _labelPrintService = const LabelPrintService(
    protocol: LabelPrinterProtocol.tspl,
  );
  final PosCartController _posCart = PosCartController();

  List<Map<String, dynamic>> _products = const [];
  Map<String, dynamic>? _selected;
  bool _initialLoading = true;
  bool _photoUploadBusy = false;

  @override
  void initState() {
    super.initState();
    _posCart.addListener(_onPosCartChanged);
    _refreshCatalog();
  }

  @override
  void dispose() {
    _posCart.removeListener(_onPosCartChanged);
    _posCart.dispose();
    super.dispose();
  }

  void _onPosCartChanged() {
    if (mounted) setState(() {});
  }

  int _stockQty(Map<String, dynamic> row) {
    return (row['stock_quantity'] as num?)?.toInt() ?? 0;
  }

  String _catalogStatus(Map<String, dynamic> row) {
    return row['status']?.toString().trim() ?? 'active';
  }

  /// Рабочий стол: только витрина в наличии (не черновики hidden, не нулевой остаток).
  bool _isShowroomRow(Map<String, dynamic> row) {
    if (_catalogStatus(row) == 'hidden') return false;
    return _stockQty(row) > 0;
  }

  String _cell(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value == null) return '—';
    final text = value.toString().trim();
    return text.isEmpty ? '—' : text;
  }

  double _weight(Map<String, dynamic> row) {
    return (row['weight_grams'] as num?)?.toDouble() ?? 0;
  }

  double _size(Map<String, dynamic> row) {
    return (row['size_value'] as num?)?.toDouble() ?? 0;
  }

  List<String> _imageUrls(Map<String, dynamic> row) =>
      productGalleryImageUrls(row);

  Future<void> _fetchAndMergeProductMedia(String sku) async {
    if (sku.isEmpty) return;

    try {
      final media = await widget.database.fetchProductMediaFieldsBySku(sku);
      if (!mounted || media == null) return;

      final selected = _selected;
      if (selected == null || _cell(selected, 'sku') != sku) return;

      setState(() {
        _selected = Map<String, dynamic>.from(selected)
          ..['additional_images'] = media['additional_images']
          ..['image_url'] = media['image_url'];
      });
    } catch (error, stackTrace) {
      debugPrint('JewelryAdminDashboard._fetchAndMergeProductMedia: $error');
      debugPrint('$stackTrace');
    }
  }

  Future<void> _selectProductRow(Map<String, dynamic> row) async {
    final sku = row['sku']?.toString().trim() ?? '';
    setState(() => _selected = row);
    await _fetchAndMergeProductMedia(sku);
  }

  Future<void> _addPhotoToSelected() async {
    final row = _selected;
    if (row == null) return;
    final sku = _cell(row, 'sku');
    if (sku == '—') return;

    final currentCount = _imageUrls(row).length;
    if (currentCount >= ProductItem.maxGalleryImages) {
      _snack('Достигнут лимит ${ProductItem.maxGalleryImages} фото', error: true);
      return;
    }

    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
    );
    if (picked == null || !mounted) return;

    setState(() => _photoUploadBusy = true);
    try {
      final bytes = await picked.readAsBytes();
      final url = await widget.database.uploadProductAdditionalImage(
        sku: sku,
        bytes: bytes,
        contentType: picked.mimeType ?? 'image/jpeg',
      );
      if (!mounted) return;
      if (url == null) {
        _snack('Не удалось загрузить фото (Storage / RLS)', error: true);
        return;
      }
      _snack('Фото ${currentCount + 1}/${ProductItem.maxGalleryImages} загружено');
      await _refreshCatalog();
    } catch (error) {
      if (!mounted) return;
      _snack('Ошибка загрузки: $error', error: true);
    } finally {
      if (mounted) setState(() => _photoUploadBusy = false);
    }
  }

  void _applyRows(List<Map<String, dynamic>> rows) {
    final active = rows.where(_isShowroomRow).toList();
    Map<String, dynamic>? selected = _selected;
    if (selected != null) {
      final sku = _cell(selected, 'sku');
      selected = null;
      for (final row in active) {
        if (_cell(row, 'sku') == sku) {
          selected = row;
          break;
        }
      }
    }
    setState(() {
      _products = active;
      _selected = selected;
    });
    if (selected != null) {
      final sku = _cell(selected, 'sku');
      if (sku != '—') {
        unawaited(_fetchAndMergeProductMedia(sku));
      }
    }
  }

  Future<void> _refreshCatalog() async {
    try {
      final rows = await widget.database.fetchAllProductRowsForAdminCatalog();
      if (!mounted) return;
      _applyRows(rows);
    } catch (error, stackTrace) {
      debugPrint('JewelryAdminDashboard._refreshCatalog failed: $error');
      debugPrint('$stackTrace');
      if (!mounted) return;
      _snack('Ошибка загрузки витрины: $error', error: true);
    } finally {
      if (mounted) setState(() => _initialLoading = false);
    }
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.saleRed : AppColors.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openDraftIntake() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DraftIntakeScreen(database: widget.database),
      ),
    );
    if (!mounted) return;
    await _refreshCatalog();
  }

  Future<void> _openAddProductDialog() async {
    await _openManualProductDialog();
  }

  Future<void> _openProductReturnDialog() async {
    await ProductReturnDialog.show(
      context,
      database: widget.database,
    );
    if (!mounted) return;
    await _refreshCatalog();
  }

  Future<void> _openEditProductDialog(Map<String, dynamic> row) async {
    await _openManualProductDialog(editProduct: row);
  }

  Future<void> _openManualProductDialog({
    Map<String, dynamic>? editProduct,
  }) async {
    final isEdit = editProduct != null;
    await showDialog<void>(
      context: context,
      builder: (context) => _ManualProductDialog(
        database: widget.database,
        editProduct: editProduct,
        catalogRows: _products,
        onSaved: ({required bool asDraft}) async {
          if (isEdit) {
            _snack('Карточка обновлена');
          } else if (asDraft) {
            _snack('Товар успешно сохранен в черновики');
          } else {
            _snack('Товар успешно добавлен на витрину');
          }
          await _refreshCatalog();
        },
      ),
    );
  }

  Future<void> _editSelectedCard() async {
    final row = _selected;
    if (row == null) {
      _snack('Выберите товар в таблице', error: true);
      return;
    }
    await _openManualProductDialog(editProduct: row);
  }

  Future<void> _writeOffSelected() async {
    final row = _selected;
    if (row == null) {
      _snack('Выберите товар в таблице', error: true);
      return;
    }
    final sku = _cell(row, 'sku');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Списать с витрины?'),
        content: Text('SKU $sku → stock_quantity = 0'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.saleRed),
            child: const Text('Списать'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final ok = await widget.database.writeOffProductBySku(sku);
      if (!ok) {
        _snack('Списание не выполнено (RLS?)', error: true);
        return;
      }
      _snack('Товар $sku снят с витрины');
      await _refreshCatalog();
    } catch (error) {
      _snack('Ошибка списания: $error', error: true);
    }
  }

  Future<void> _addSelectedToPosCart() async {
    final row = _selected;
    if (row == null) {
      _snack('Выберите товар в таблице', error: true);
      return;
    }
    final sku = row['sku']?.toString().trim() ?? '';
    if (sku.isNotEmpty) {
      await _fetchAndMergeProductMedia(sku);
    }
    final currentRow = _selected ?? row;
    try {
      final product = ProductItem.fromJson(
        CloudDatabaseService.productRowToClientJson(currentRow),
      );
      if (!_posCart.containsProduct(product.id)) {
        _posCart.addToCart(product);
        _snack('В POS-корзине: ${product.sku}');
      } else {
        _snack('Уже в POS-корзине: ${product.sku}');
      }
    } catch (error) {
      _snack('Не удалось добавить в корзину: $error', error: true);
    }
  }

  Future<void> _openPosCartSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => AdminPosCartSheet(
        cart: _posCart,
        database: widget.database,
        onArchived: () async {
          _posCart.clearCart();
          await _refreshCatalog();
          widget.onPosSaleArchived?.call();
        },
      ),
    );
  }

  Future<void> _markSoldSelected() async {
    final row = _selected;
    if (row == null) {
      _snack('Выберите товар в таблице', error: true);
      return;
    }
    final sku = _cell(row, 'sku');
    final productId = row['id']?.toString().trim() ?? '';
    if (productId.isEmpty) {
      _snack('У позиции нет id', error: true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Продано'),
        content: Text(
          'Зафиксировать ручную продажу изделия $sku и перенести в историю продаж?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1B5E20),
            ),
            child: const Text('Продано'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final ok = await widget.database.markProductSoldByProductId(productId);
      if (!ok) {
        _snack('Продажа не зафиксирована (RLS?)', error: true);
        return;
      }
      _snack('Продажа $sku зафиксирована · история обновится на сервере');
      await _refreshCatalog();
    } catch (error) {
      _snack('Ошибка продажи: $error', error: true);
    }
  }

  Future<void> _printDuplicateLabel() async {
    final row = _selected;
    if (row == null) {
      _snack('Выберите товар в таблице', error: true);
      return;
    }

    final labelData = JewelryLabelData.fromProductMap(row);
    final sku = _cell(row, 'sku');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            'Дубликат бирки · $sku',
            style: AppTypography.heading(fontSize: 18),
          ),
          content: SingleChildScrollView(
            child: JewelryLabelPreview(data: labelData),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Печатать'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    try {
      await _labelPrintService.printLabel(labelData);
      _snack('Дубликат бирки отправлен на печать (TSPL)');
    } catch (error, stackTrace) {
      debugPrint('JewelryAdminDashboard._printDuplicateLabel failed: $error');
      debugPrint('$stackTrace');
      _snack('Ошибка печати: $error', error: true);
    }
  }

  double get _totalWeightGrams =>
      _products.fold(0.0, (sum, row) => sum + _weight(row));

  int get _totalPriceKrw => _products.fold(
        0,
        (sum, row) => sum + (adminShowroomSalePriceKrw(row) ?? 0),
      );

  Map<String, ShowroomStoreSelectionStats> get _storeSelectionStats =>
      computeShowroomStatsByStore(
        products: _products,
        priceKrwForRow: (row) => adminShowroomSalePriceKrw(row) ?? 0,
        weightGramsForRow: _weight,
      );

  @override
  Widget build(BuildContext context) {
    final profile = ProfileScope.of(context);
    final isSuperAdmin = AdminAccess.isSuperAdmin(
      supabaseUser: Supabase.instance.client.auth.currentUser,
      localPanelAdmin: profile.isLocalAdminAuthenticated,
    );
    final selectedSku = _selected == null ? null : _cell(_selected!, 'sku');

    return Scaffold(
      backgroundColor: AppColors.background,
      body: _initialLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TopControlBar(
                    database: widget.database,
                    isSuperAdmin: isSuperAdmin,
                    onFilterApplied: _applyRows,
                    onOpenDraft: _openDraftIntake,
                    onAddProduct: _openAddProductDialog,
                    onProductReturn: _openProductReturnDialog,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 3,
                          child: _ProductTablePanel(
                            products: _products,
                            selectedSku: selectedSku,
                            isSuperAdmin: isSuperAdmin,
                            onSelect: _selectProductRow,
                            onEdit: _openEditProductDialog,
                            cell: _cell,
                            insertLabel: adminProductInsertLabel,
                            productName: extractStoredProductName,
                            salePriceLabel: adminShowroomSalePriceLabel,
                            weight: _weight,
                            size: _size,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: _MediaAndKpiPanel(
                            selected: _selected,
                            imageUrls: _selected == null
                                ? const []
                                : _imageUrls(_selected!),
                            totalCount: _products.length,
                            totalWeightGrams: _totalWeightGrams,
                            totalPriceKrw: _totalPriceKrw,
                            storeStats: _storeSelectionStats,
                            cell: _cell,
                            weight: _weight,
                            photoUploadBusy: _photoUploadBusy,
                            onAddPhoto: _addPhotoToSelected,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _BottomActionBar(
                    hasSelection: _selected != null,
                    isSuperAdmin: isSuperAdmin,
                    posCartCount: _posCart.lineCount,
                    onAddToPosCart: _addSelectedToPosCart,
                    onOpenPosCart: _openPosCartSheet,
                    onPrint: _printDuplicateLabel,
                    onEdit: _editSelectedCard,
                    onMarkSold: _markSoldSelected,
                    onWriteOff: _writeOffSelected,
                  ),
                ],
              ),
            ),
    );
  }
}

class _TopControlBar extends StatelessWidget {
  const _TopControlBar({
    required this.database,
    required this.isSuperAdmin,
    required this.onFilterApplied,
    required this.onOpenDraft,
    required this.onAddProduct,
    required this.onProductReturn,
  });

  final DatabaseService database;
  final bool isSuperAdmin;
  final void Function(List<Map<String, dynamic>> products) onFilterApplied;
  final VoidCallback onOpenDraft;
  final VoidCallback onAddProduct;
  final VoidCallback onProductReturn;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.end,
              children: [
                if (isSuperAdmin) ...[
                  OutlinedButton.icon(
                    onPressed: onOpenDraft,
                    icon: const Icon(Icons.move_to_inbox_outlined),
                    label: const Text('Перейти в режим Приёмки (Черновики)'),
                  ),
                  FilledButton.icon(
                    onPressed: onAddProduct,
                    icon: const Icon(Icons.add_circle_outline),
                    label: const Text('Добавить товар'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.textOnPrimary,
                    ),
                  ),
                ],
                OutlinedButton.icon(
                  onPressed: onProductReturn,
                  icon: const Icon(Icons.replay_outlined),
                  label: const Text('Возврат товара'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SmartFilterWidget(
              database: database,
              onFilterApplied: onFilterApplied,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductTablePanel extends StatefulWidget {
  const _ProductTablePanel({
    required this.products,
    required this.selectedSku,
    required this.isSuperAdmin,
    required this.onSelect,
    required this.onEdit,
    required this.cell,
    required this.insertLabel,
    required this.productName,
    required this.salePriceLabel,
    required this.weight,
    required this.size,
  });

  final List<Map<String, dynamic>> products;
  final String? selectedSku;
  final bool isSuperAdmin;
  final ValueChanged<Map<String, dynamic>> onSelect;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final String Function(Map<String, dynamic>, String) cell;
  final String Function(Map<String, dynamic>) insertLabel;
  final String Function(Map<String, dynamic>) productName;
  final String Function(Map<String, dynamic>) salePriceLabel;
  final double Function(Map<String, dynamic>) weight;
  final double Function(Map<String, dynamic>) size;

  @override
  State<_ProductTablePanel> createState() => _ProductTablePanelState();
}

class _ProductTablePanelState extends State<_ProductTablePanel> {
  final ScrollController _horizontalScroll = ScrollController();
  final ScrollController _verticalScroll = ScrollController();

  @override
  void dispose() {
    _horizontalScroll.dispose();
    _verticalScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final products = widget.products;
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: products.isEmpty
          ? Center(
              child: Text(
                'Нет активных позиций (stock_quantity > 0)',
                style: AppTypography.productMeta(),
              ),
            )
          : Scrollbar(
              controller: _horizontalScroll,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _horizontalScroll,
                scrollDirection: Axis.horizontal,
                child: Scrollbar(
                  controller: _verticalScroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _verticalScroll,
                    scrollDirection: Axis.vertical,
                    child: IntrinsicWidth(
                      child: DataTable(
                        columnSpacing: 28,
                        horizontalMargin: 20,
                        showCheckboxColumn: false,
                        headingRowColor: WidgetStateProperty.all(
                          AppColors.cardBackground,
                        ),
                        columns: const [
                          DataColumn(label: Text('Артикул (SKU)')),
                          DataColumn(label: Text('Магазин')),
                          DataColumn(label: Text('Металл')),
                          DataColumn(label: Text('Вес, г')),
                          DataColumn(label: Text('Размер')),
                          DataColumn(label: Text('Вставки')),
                          DataColumn(label: Text('Цена')),
                          DataColumn(label: Text('Описание')),
                          DataColumn(label: Text('')),
                        ],
                        rows: products.map((row) {
                          final sku = widget.cell(row, 'sku');
                          final selected = sku == widget.selectedSku;
                          return DataRow(
                            selected: selected,
                            onSelectChanged: (_) => widget.onSelect(row),
                            color: WidgetStateProperty.resolveWith((states) {
                              if (selected) {
                                return AppColors.accent.withValues(alpha: 0.12);
                              }
                              return null;
                            }),
                            cells: [
                              DataCell(Text(sku)),
                              DataCell(
                                _StoreLocationBadge(row: row),
                              ),
                              DataCell(Text(widget.cell(row, 'metal'))),
                              DataCell(
                                Text(widget.weight(row).toStringAsFixed(2)),
                              ),
                              DataCell(
                                Text(widget.size(row).toStringAsFixed(2)),
                              ),
                              DataCell(Text(widget.insertLabel(row))),
                              DataCell(Text(widget.salePriceLabel(row))),
                              DataCell(
                                SizedBox(
                                  width: 220,
                                  child: Text(
                                    widget.productName(row),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                              DataCell(
                                widget.isSuperAdmin
                                    ? IconButton(
                                        tooltip: 'Редактировать карточку',
                                        icon: const Text(
                                          '✏️',
                                          style: TextStyle(fontSize: 18),
                                        ),
                                        onPressed: () => widget.onEdit(row),
                                      )
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _MediaAndKpiPanel extends StatelessWidget {
  const _MediaAndKpiPanel({
    required this.selected,
    required this.imageUrls,
    required this.totalCount,
    required this.totalWeightGrams,
    required this.totalPriceKrw,
    required this.storeStats,
    required this.cell,
    required this.weight,
    required this.photoUploadBusy,
    required this.onAddPhoto,
  });

  final Map<String, dynamic>? selected;
  final List<String> imageUrls;
  final int totalCount;
  final double totalWeightGrams;
  final int totalPriceKrw;
  final Map<String, ShowroomStoreSelectionStats> storeStats;
  final String Function(Map<String, dynamic>, String) cell;
  final double Function(Map<String, dynamic>) weight;
  final bool photoUploadBusy;
  final VoidCallback onAddPhoto;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('KPI витрины (текущая выборка)', style: AppTypography.heading(fontSize: 16)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _KpiTile(
                    label: 'Позиций',
                    value: '$totalCount',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _KpiTile(
                    label: 'Суммарная масса',
                    value: '${totalWeightGrams.toStringAsFixed(2)} г',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _KpiTile(
                    label: 'Общая сумма',
                    value: adminShowroomKrwLabel(totalPriceKrw),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _KpiStoreBreakdown(storeStats: storeStats),
            const SizedBox(height: 20),
            Text(
              selected == null
                  ? 'Фото товара'
                  : 'Фото · ${cell(selected!, 'sku')}',
              style: AppTypography.heading(fontSize: 16),
            ),
            const SizedBox(height: 12),
            _ProductPhotoGrid(imageUrls: imageUrls),
            if (selected != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: photoUploadBusy ||
                          imageUrls.length >= ProductItem.maxGalleryImages
                      ? null
                      : onAddPhoto,
                  icon: photoUploadBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(
                    'Добавить фото (${imageUrls.length}/${ProductItem.maxGalleryImages})',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Масса выбранного: ${weight(selected!).toStringAsFixed(2)} г',
                style: AppTypography.productMeta(),
              ),
              Text(
                'Магазин: ${storeLocationDisplayLabelForRow(selected!)}',
                style: AppTypography.productMeta(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _KpiStoreBreakdown extends StatelessWidget {
  const _KpiStoreBreakdown({required this.storeStats});

  final Map<String, ShowroomStoreSelectionStats> storeStats;

  String _line(String code, String title) {
    final stats = storeStats[code] ?? const ShowroomStoreSelectionStats();
    return '$title: ${stats.count} шт · '
        '${stats.weightGrams.toStringAsFixed(2)} г · '
        '${adminShowroomKrwLabel(stats.priceKrw)}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'По магазинам',
            style: AppTypography.productMeta().copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _line(StoreLocationCode.icn, 'Инчхон'),
            style: AppTypography.productMeta(),
          ),
          const SizedBox(height: 4),
          Text(
            _line(StoreLocationCode.ans, 'Ансан'),
            style: AppTypography.productMeta(),
          ),
        ],
      ),
    );
  }
}

class _StoreLocationBadge extends StatelessWidget {
  const _StoreLocationBadge({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final code = storeLocationCodeFromProductRow(row);
    final label = storeLocationDisplayLabelForRow(row);
    final colors = storeLocationBadgeColors(code);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.fg.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: AppTypography.productMeta().copyWith(
          color: colors.fg,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTypography.productMeta(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: AppTypography.heading(fontSize: 18),
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductPhotoGrid extends StatelessWidget {
  const _ProductPhotoGrid({required this.imageUrls});

  final List<String> imageUrls;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: List.generate(ProductItem.maxGalleryImages, (index) {
        final url = index < imageUrls.length ? imageUrls[index] : null;
        return _PhotoSlot(url: url);
      }),
    );
  }
}

class _PhotoSlot extends StatelessWidget {
  const _PhotoSlot({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: url == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.image_not_supported_outlined,
                    color: AppColors.textSecondary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 4),
                  Text('Нет фото', style: AppTypography.productMeta()),
                ],
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  url!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.broken_image_outlined),
                ),
              ),
      ),
    );
  }
}

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({
    required this.hasSelection,
    required this.isSuperAdmin,
    required this.posCartCount,
    required this.onAddToPosCart,
    required this.onOpenPosCart,
    required this.onPrint,
    required this.onEdit,
    required this.onMarkSold,
    required this.onWriteOff,
  });

  final bool hasSelection;
  final bool isSuperAdmin;
  final int posCartCount;
  final VoidCallback onAddToPosCart;
  final VoidCallback onOpenPosCart;
  final VoidCallback onPrint;
  final VoidCallback onEdit;
  final VoidCallback onMarkSold;
  final VoidCallback onWriteOff;

  static const _soldGreen = Color(0xFF1B5E20);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: hasSelection ? onAddToPosCart : null,
              icon: const Icon(Icons.add_shopping_cart_outlined),
              label: const Text('В POS-корзину'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
              ),
            ),
            Badge(
              isLabelVisible: posCartCount > 0,
              label: Text('$posCartCount'),
              child: OutlinedButton.icon(
                onPressed: onOpenPosCart,
                icon: const Icon(Icons.shopping_cart_checkout_outlined),
                label: Text(
                  posCartCount > 0
                      ? 'POS-корзина ($posCartCount)'
                      : 'POS-корзина',
                ),
              ),
            ),
            FilledButton.tonalIcon(
              onPressed: hasSelection ? onPrint : null,
              icon: const Icon(Icons.print_outlined),
              label: const Text('Распечатать дубликат бирки'),
            ),
            if (isSuperAdmin) ...[
              OutlinedButton.icon(
                onPressed: hasSelection ? onEdit : null,
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Редактировать карточку'),
              ),
              FilledButton.icon(
                onPressed: hasSelection ? onMarkSold : null,
                icon: const Icon(Icons.handshake_outlined),
                label: const Text('Продано'),
                style: FilledButton.styleFrom(
                  backgroundColor: _soldGreen,
                  foregroundColor: Colors.white,
                ),
              ),
              OutlinedButton.icon(
                onPressed: hasSelection ? onWriteOff : null,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Списать / Изъять с витрины'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.saleRed,
                  side: const BorderSide(color: AppColors.saleRed),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Слепок формы «Добавить товар» для детекции повторного сохранения без изменений.
class _ManualFormSnapshot {
  const _ManualFormSnapshot({
    required this.sku,
    required this.weightText,
    required this.sizeText,
    required this.priceDigits,
    required this.productTypeCategory,
    required this.subtypeDropdown,
    required this.customSubtype,
    required this.customName,
    required this.manufacturerCategory,
    required this.customManufacturer,
    required this.metalCategory,
    required this.goldType,
    required this.silverType,
    required this.catalogGems,
    required this.legacyGems,
    required this.notes,
    required this.imageUrls,
    required this.deferredPhotoKeys,
  });

  final String sku;
  final String weightText;
  final String sizeText;
  final String priceDigits;
  final String productTypeCategory;
  final String subtypeDropdown;
  final String customSubtype;
  final String customName;
  final String manufacturerCategory;
  final String customManufacturer;
  final String metalCategory;
  final String goldType;
  final String silverType;
  final List<String> catalogGems;
  final List<String> legacyGems;
  final String notes;
  final List<String> imageUrls;
  final List<String> deferredPhotoKeys;

  factory _ManualFormSnapshot.fromState(_ManualProductDialogState state) {
    final priceDigits = state._priceController.text
        .replaceAll(RegExp(r'[^\d]'), '')
        .trim();
    final deferredKeys = state._deferredPhotos
        .map((f) => '${f.name}|${f.path}|${f.hashCode}')
        .toList()
      ..sort();
    return _ManualFormSnapshot(
      sku: state._skuController.text.trim(),
      weightText: state._weightController.text.trim().replaceAll(',', '.'),
      sizeText: state._sizeController.text.trim().replaceAll(',', '.'),
      priceDigits: priceDigits,
      productTypeCategory: state._productTypeCategory,
      subtypeDropdown: state._subtypeDropdown,
      customSubtype: state._customSubtypeController.text.trim(),
      customName: state._customNameController.text.trim(),
      manufacturerCategory: state._manufacturerCategory,
      customManufacturer: state._customManufacturerController.text.trim(),
      metalCategory: state._metalCategory,
      goldType: state._goldType,
      silverType: state._silverType,
      catalogGems: state._selectedCatalogGems.toList()..sort(),
      legacyGems: List<String>.from(state._legacyGemValues)..sort(),
      notes: state._notesController.text.trim(),
      imageUrls: List<String>.from(state._imageUrls)..sort(),
      deferredPhotoKeys: deferredKeys,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _ManualFormSnapshot &&
        sku == other.sku &&
        weightText == other.weightText &&
        sizeText == other.sizeText &&
        priceDigits == other.priceDigits &&
        productTypeCategory == other.productTypeCategory &&
        subtypeDropdown == other.subtypeDropdown &&
        customSubtype == other.customSubtype &&
        customName == other.customName &&
        manufacturerCategory == other.manufacturerCategory &&
        customManufacturer == other.customManufacturer &&
        metalCategory == other.metalCategory &&
        goldType == other.goldType &&
        silverType == other.silverType &&
        _listEquals(catalogGems, other.catalogGems) &&
        _listEquals(legacyGems, other.legacyGems) &&
        notes == other.notes &&
        _listEquals(imageUrls, other.imageUrls) &&
        _listEquals(deferredPhotoKeys, other.deferredPhotoKeys);
  }

  @override
  int get hashCode => Object.hashAll([
        sku,
        weightText,
        sizeText,
        priceDigits,
        productTypeCategory,
        subtypeDropdown,
        customSubtype,
        customName,
        manufacturerCategory,
        customManufacturer,
        metalCategory,
        goldType,
        silverType,
        Object.hashAll(catalogGems),
        Object.hashAll(legacyGems),
        notes,
        Object.hashAll(imageUrls),
        Object.hashAll(deferredPhotoKeys),
      ]);

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _ManualInlineNotice extends StatelessWidget {
  const _ManualInlineNotice({
    required this.message,
    required this.pulse,
    required this.success,
  });

  final String message;
  final int pulse;
  final bool? success;

  @override
  Widget build(BuildContext context) {
    final borderColor = success == true
        ? const Color(0xFF1B5E20)
        : const Color(0xFFE65100);
    final fillColor = success == true
        ? const Color(0xFF2E7D32).withValues(alpha: 0.16)
        : const Color(0xFFF57C00).withValues(alpha: 0.14);
    final textColor =
        success == true ? const Color(0xFF1B5E20) : const Color(0xFFBF360C);

    return TweenAnimationBuilder<double>(
      key: ValueKey<int>(pulse),
      tween: Tween(begin: 0.94, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          alignment: Alignment.center,
          child: child,
        );
      },
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: fillColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: borderColor, width: 1.2),
        ),
        child: Text(
          message,
          style: AppTypography.productMeta().copyWith(
            color: textColor,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

class _ManualSaveBanner extends StatelessWidget {
  const _ManualSaveBanner({
    required this.message,
    required this.pulse,
  });

  final String message;
  final int pulse;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey<int>(pulse),
      tween: Tween(begin: 0.94, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOut,
      builder: (context, scale, child) {
        return Transform.scale(
          scale: scale,
          alignment: Alignment.center,
          child: child,
        );
      },
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF2E7D32).withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF1B5E20), width: 1.2),
        ),
        child: Text(
          message,
          style: AppTypography.productMeta().copyWith(
            color: const Color(0xFF1B5E20),
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

class _ManualProductDialog extends StatefulWidget {
  const _ManualProductDialog({
    required this.database,
    required this.onSaved,
    this.editProduct,
    this.catalogRows = const [],
  });

  final DatabaseService database;
  final Future<void> Function({required bool asDraft}) onSaved;
  final Map<String, dynamic>? editProduct;
  final List<Map<String, dynamic>> catalogRows;

  bool get isEditMode => editProduct != null;

  @override
  State<_ManualProductDialog> createState() => _ManualProductDialogState();
}

class _ManualProductDialogState extends State<_ManualProductDialog> {
  static const _manufacturerOptions = [
    'Sokolov',
    'Диамант',
    'DINASTIA',
    'new gold',
    'Ганибал',
    'Елена',
    'BEST',
    'caravan',
    'SOFIZAR',
    'UZ GOLD',
    'volkov',
    'Виноградов',
    'Высоковы',
    'Гиалит',
    'Диана',
    'Макс',
    'ОАЗИС',
    'Другое',
  ];

  final _skuController = TextEditingController();
  final _customNameController = TextEditingController();
  final _customSubtypeController = TextEditingController();
  final _customManufacturerController = TextEditingController();
  final _weightController = TextEditingController();
  final _sizeController = TextEditingController();
  final _priceController = TextEditingController();
  final _gemController = TextEditingController();
  final _notesController = TextEditingController();

  Set<String> _selectedCatalogGems = {};
  List<String> _legacyGemValues = [];

  String _productTypeCategory = kJewelryMainCategories.first;
  String _subtypeDropdown = kJewelrySubtypeUnspecified;
  String _manufacturerCategory = _manufacturerOptions.first;
  String _metalCategory = 'gold';
  String _goldType = '585 красное';
  String _silverType = '925 Родированное';
  String _storeLocationCode = StoreLocationCode.defaultCode;
  bool _saving = false;
  bool _keepFieldsAfterSave = false;
  int _sessionSaveCount = 0;
  int _saveBannerPulse = 0;
  String? _saveBannerMessage;
  _ManualFormSnapshot? _lastSavedSnapshot;
  bool _skuPhotoLookupInProgress = false;
  String? _photoLookupMessage;
  int _photoLookupPulse = 0;
  bool? _photoLookupSuccess;

  List<String> _imageUrls = [];
  final List<XFile> _deferredPhotos = [];

  static const _goldTypes = [
    '585 красное',
    '585 жёлтое',
    '585 белое',
    '750 жёлтое',
    '750 белое',
  ];

  static const _silverTypes = [
    '925 Родированное',
    '925 Позолоченное',
    '925 Комбинированное',
    '925 чернение',
  ];

  bool get _isEditMode => widget.isEditMode;

  int get _totalPhotoCount => _imageUrls.length + _deferredPhotos.length;

  String get _resolvedMetalType =>
      _metalCategory == 'gold' ? _goldType : _silverType;

  String? get _resolvedSubtypeForSave {
    if (_productTypeCategory == kJewelryCategoryOther) return null;
    if (_subtypeDropdown == kJewelrySubtypeUnspecified) return null;
    if (_subtypeDropdown == kJewelrySubtypeCustom) {
      final custom = _customSubtypeController.text.trim();
      return custom.isEmpty ? null : custom;
    }
    return _subtypeDropdown;
  }

  String get _resolvedProductCategory {
    if (_productTypeCategory == kJewelryCategoryOther) {
      return _customNameController.text.trim();
    }
    return _productTypeCategory;
  }

  String get _resolvedProductDisplayName {
    if (_productTypeCategory == kJewelryCategoryOther) {
      return _customNameController.text.trim();
    }
    return formatJewelryProductDisplayName(
      mainCategory: _productTypeCategory,
      subtype: _resolvedSubtypeForSave,
    );
  }

  bool get _showSubtypePicker =>
      _productTypeCategory != kJewelryCategoryOther &&
      kJewelryCategorySubtypes.containsKey(_productTypeCategory);

  bool get _showCustomSubtypeField =>
      _showSubtypePicker && _subtypeDropdown == kJewelrySubtypeCustom;

  String get _customSubtypeHint {
    if (_productTypeCategory == 'Гайтан') {
      return 'Например: кожаный, капроновый';
    }
    if (_productTypeCategory == 'Пирсинг') {
      return 'Например: в нос, в бровь';
    }
    return 'Введите вид изделия';
  }

  String get _resolvedManufacturer {
    if (_manufacturerCategory == 'Другое') {
      return _customManufacturerController.text.trim();
    }
    return _manufacturerCategory;
  }

  List<String> get _metalDropdownOptions {
    final base = _metalCategory == 'gold'
        ? List<String>.from(_goldTypes)
        : List<String>.from(_silverTypes);
    final current = _resolvedMetalType;
    if (current.isNotEmpty && !base.contains(current)) {
      base.insert(0, current);
    }
    return base;
  }

  @override
  void initState() {
    super.initState();
    final edit = widget.editProduct;
    if (edit == null) {
      unawaited(_restoreLastSelectedMetalForAddMode());
      unawaited(_restoreLastSelectedStoreForAddMode());
      return;
    }

    _storeLocationCode = storeLocationCodeFromProductRow(edit);

    _skuController.text = edit['sku']?.toString().trim() ?? '';
    _weightController.text = _formatNumField(edit['weight_grams']);
    _sizeController.text = _formatNumField(edit['size_value']);
    final parsed = parseGemInsertsFromProductField(
      edit['gem_inserts'] ?? edit['insert'],
    );
    _selectedCatalogGems = Set<String>.from(parsed.catalog);
    _legacyGemValues = parsed.legacy.toList();
    _syncGemControllerFromSelection();
    _notesController.text = edit['notes']?.toString().trim() ?? '';
    _initPriceField(edit);
    _applyMetalFromStored(
      (edit['metal_type'] ?? edit['metal'])?.toString() ?? '',
    );
    _imageUrls = List<String>.from(productGalleryImageUrls(edit));
    _initCategoryFields(edit);
    _initManufacturerFields(edit['manufacturer']?.toString().trim() ?? '');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_hydrateGalleryFromServer());
    });
  }

  Future<void> _restoreLastSelectedMetalForAddMode() async {
    try {
      final storage = await AdminManualProductStorage.create();
      final category = storage.lastSelectedMetalCategory;
      if (category == null || !mounted) return;
      setState(() => _metalCategory = category);
    } catch (error, stackTrace) {
      debugPrint(
        '_ManualProductDialog._restoreLastSelectedMetalForAddMode: $error',
      );
      debugPrint('$stackTrace');
    }
  }

  Future<void> _persistLastSelectedMetalCategory(String category) async {
    if (_isEditMode) return;
    try {
      final storage = await AdminManualProductStorage.create();
      await storage.saveLastSelectedMetalCategory(category);
    } catch (error, stackTrace) {
      debugPrint(
        '_ManualProductDialog._persistLastSelectedMetalCategory: $error',
      );
      debugPrint('$stackTrace');
    }
  }

  Future<void> _restoreLastSelectedStoreForAddMode() async {
    try {
      final storage = await AdminManualProductStorage.create();
      if (!mounted) return;
      setState(() => _storeLocationCode = storage.lastSelectedStoreLocation);
    } catch (error, stackTrace) {
      debugPrint(
        '_ManualProductDialog._restoreLastSelectedStoreForAddMode: $error',
      );
      debugPrint('$stackTrace');
    }
  }

  Future<void> _persistLastSelectedStoreLocation(String code) async {
    if (_isEditMode) return;
    try {
      final storage = await AdminManualProductStorage.create();
      await storage.saveLastSelectedStoreLocation(code);
    } catch (error, stackTrace) {
      debugPrint(
        '_ManualProductDialog._persistLastSelectedStoreLocation: $error',
      );
      debugPrint('$stackTrace');
    }
  }

  Future<void> _hydrateGalleryFromServer() async {
    if (!_isEditMode) return;
    final sku = _skuController.text.trim();
    if (sku.isEmpty) return;
    try {
      final media = await widget.database.fetchProductMediaFieldsBySku(sku);
      if (!mounted || media == null) return;
      final merged = Map<String, dynamic>.from(widget.editProduct!)
        ..addAll(media);
      final urls = productGalleryImageUrls(merged);
      if (urls.isEmpty) return;
      setState(() => _imageUrls = List<String>.from(urls));
    } catch (error, stackTrace) {
      debugPrint('_ManualProductDialog._hydrateGalleryFromServer: $error');
      debugPrint('$stackTrace');
    }
  }

  void _initManufacturerFields(String storedManufacturer) {
    if (storedManufacturer.isEmpty) return;
    if (_manufacturerOptions.contains(storedManufacturer)) {
      _manufacturerCategory = storedManufacturer;
      return;
    }
    _manufacturerCategory = 'Другое';
    _customManufacturerController.text = storedManufacturer;
  }

  void _initPriceField(Map<String, dynamic> row) {
    final raw = row['price'] ?? row['sale_price'];
    if (raw == null) return;
    if (raw is num) {
      final value = raw.toInt();
      if (value > 0) {
        _priceController.text = '$value';
      }
      return;
    }
    final text = raw.toString().trim();
    if (text.isNotEmpty) {
      _priceController.text = text;
    }
  }

  void _initCategoryFields(Map<String, dynamic> edit) {
    final nameText = extractStoredProductName(edit);
    final parsed = parseJewelryProductCategoryFromRow(
      nameText: nameText == '—' ? null : nameText,
      categoryColumn: edit['category']?.toString(),
    );

    if (parsed.isOther) {
      _productTypeCategory = kJewelryCategoryOther;
      _customNameController.text = parsed.displayName;
      _subtypeDropdown = kJewelrySubtypeUnspecified;
      _customSubtypeController.clear();
      return;
    }

    _productTypeCategory = parsed.mainCategory;
    _customNameController.clear();
    if (parsed.catalogSubtype != null) {
      _subtypeDropdown = parsed.catalogSubtype!;
      _customSubtypeController.clear();
    } else if (parsed.customSubtype != null &&
        parsed.customSubtype!.isNotEmpty) {
      _subtypeDropdown = kJewelrySubtypeCustom;
      _customSubtypeController.text = parsed.customSubtype!;
    } else {
      _subtypeDropdown = kJewelrySubtypeUnspecified;
      _customSubtypeController.clear();
    }
  }

  void _syncGemControllerFromSelection() {
    _gemController.text = formatGemInsertsForStorage(
      catalog: _selectedCatalogGems,
      legacy: _legacyGemValues,
    );
  }

  Future<void> _openGemInsertsPicker() async {
    final result = await showJewelryGemInsertPickerDialog(
      context: context,
      initialCatalog: _selectedCatalogGems,
      initialLegacy: _legacyGemValues,
    );
    if (result == null || !mounted) return;
    setState(() {
      _selectedCatalogGems = Set<String>.from(result.catalog);
      _legacyGemValues = List<String>.from(result.legacy);
      _syncGemControllerFromSelection();
    });
  }

  Future<void> _confirmRemoveNetworkPhoto(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить фото?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.saleRed,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (index < 0 || index >= _imageUrls.length) return;
    setState(() => _imageUrls = List<String>.from(_imageUrls)..removeAt(index));
  }

  Future<void> _confirmRemoveDeferredPhoto(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить фото?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.saleRed,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (index < 0 || index >= _deferredPhotos.length) return;
    setState(() => _deferredPhotos.removeAt(index));
  }

  @override
  void dispose() {
    _skuController.dispose();
    _customNameController.dispose();
    _customManufacturerController.dispose();
    _customSubtypeController.dispose();
    _weightController.dispose();
    _sizeController.dispose();
    _priceController.dispose();
    _gemController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  static String _formatNumField(Object? value) {
    if (value == null) return '';
    if (value is num) {
      final d = value.toDouble();
      if (d == d.roundToDouble()) return '${d.toInt()}';
      return d.toStringAsFixed(2);
    }
    return value.toString().trim();
  }

  void _applyMetalFromStored(String metalType) {
    final stored = metalType.trim();
    if (stored.isEmpty) return;

    final lower = stored.toLowerCase();
    final isSilver = lower.contains('сереб') ||
        lower.contains('925') ||
        _silverTypes.any((probe) => lower.contains(probe.toLowerCase()));

    if (isSilver) {
      _metalCategory = 'silver';
      _silverType = _silverTypes.firstWhere(
        (probe) => stored == probe || stored.contains(probe),
        orElse: () => _silverTypes.first,
      );
    } else {
      _metalCategory = 'gold';
      _goldType = _goldTypes.firstWhere(
        (item) => stored == item,
        orElse: () => _goldTypes.firstWhere(
          (item) => stored.contains(item.split(' ').first),
          orElse: () => stored,
        ),
      );
      if (!_goldTypes.contains(_goldType)) {
        _goldType = _goldTypes.first;
      }
    }
  }

  void _applyProbe585() {
    setState(() {
      _metalCategory = 'gold';
      _goldType = '585 красное';
    });
  }

  void _applyProbe925() {
    setState(() {
      _metalCategory = 'silver';
      _silverType = '925 Родированное';
    });
  }

  void _showPhotoLookupNotice({
    required String message,
    required bool? success,
  }) {
    setState(() {
      _photoLookupMessage = message;
      _photoLookupSuccess = success;
      _photoLookupPulse++;
    });
  }

  int _mergeDiscoveredImageUrls(List<String> found) {
    final seen = {..._imageUrls};
    final merged = List<String>.from(_imageUrls);
    var added = 0;
    for (final raw in found) {
      final url = raw.trim();
      if (url.isEmpty || seen.contains(url)) continue;
      if (merged.length >= ProductItem.maxGalleryImages) break;
      seen.add(url);
      merged.add(url);
      added++;
    }
    setState(() => _imageUrls = merged);
    return added;
  }

  Future<void> _lookupPhotosBySku() async {
    if (_skuPhotoLookupInProgress || _saving) return;
    final sku = _skuController.text.trim();
    if (sku.isEmpty) {
      _showPhotoLookupNotice(
        message: 'Введите артикул для поиска фото',
        success: false,
      );
      return;
    }

    setState(() => _skuPhotoLookupInProgress = true);
    try {
      final found = await widget.database.findProductImagesBySku(
        sku,
        catalogRows: widget.catalogRows,
      );
      if (!mounted) return;
      if (found.isEmpty) {
        _showPhotoLookupNotice(
          message: 'Фото по артикулу «$sku» в базе не найдены',
          success: false,
        );
        return;
      }
      final added = _mergeDiscoveredImageUrls(found);
      if (added == 0) {
        _showPhotoLookupNotice(
          message: 'Все найденные фото уже добавлены в карточку',
          success: false,
        );
        return;
      }
      _showPhotoLookupNotice(
        message: '✓ Подтянуто фото по артикулу: $added шт.',
        success: true,
      );
    } catch (error) {
      if (!mounted) return;
      _showPhotoLookupNotice(
        message: 'Не удалось найти фото: $error',
        success: false,
      );
    } finally {
      if (mounted) setState(() => _skuPhotoLookupInProgress = false);
    }
  }

  Future<void> _pickPhoto() async {
    if (_totalPhotoCount >= ProductItem.maxGalleryImages) {
      _snack('Лимит ${ProductItem.maxGalleryImages} фото', error: true);
      return;
    }

    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
    );
    if (picked == null || !mounted) return;

    setState(() => _deferredPhotos.add(picked));
  }

  Future<List<String>> _uploadDeferredPhotos(String sku) async {
    final uploaded = <String>[];
    for (final file in _deferredPhotos) {
      final bytes = await file.readAsBytes();
      final url = await widget.database.uploadProductAdditionalImage(
        sku: sku,
        bytes: bytes,
        contentType: file.mimeType ?? 'image/jpeg',
      );
      if (url == null) {
        throw StateError('Не удалось загрузить ${file.name}');
      }
      uploaded.add(url);
    }
    return uploaded;
  }

  List<String> _mergeManualGalleryUrls({
    required List<String> retained,
    required List<String> uploaded,
  }) {
    final seen = <String>{};
    final merged = <String>[];
    for (final raw in [...retained, ...uploaded]) {
      final url = raw.trim();
      if (url.isEmpty || seen.contains(url)) continue;
      seen.add(url);
      merged.add(url);
      if (merged.length >= ProductItem.maxGalleryImages) break;
    }
    return merged;
  }

  /// После insert: локальные файлы → Storage; удерживаемые URL из предыдущего
  /// сохранения пишем в новую строку через ту же галерею, что и при редактировании.
  Future<void> _attachGalleryForNewManualProduct(String sku) async {
    final retained = List<String>.from(_imageUrls);
    var uploaded = <String>[];
    if (_deferredPhotos.isNotEmpty) {
      uploaded = await _uploadDeferredPhotos(sku);
      if (mounted) setState(() => _deferredPhotos.clear());
    }

    final merged = _mergeManualGalleryUrls(
      retained: retained,
      uploaded: uploaded,
    );
    if (merged.isEmpty) return;

    final row = await widget.database.fetchProductRowForLabelBySku(sku);
    final productId = row?['id']?.toString().trim() ?? '';
    if (productId.isEmpty) return;

    final galleryOk = await widget.database.updateProductGalleryByProductId(
      productId: productId,
      additionalImages: merged,
    );
    if (!galleryOk && mounted) {
      _snack('Товар сохранён, но галерея фото не обновилась', error: true);
    }
    if (mounted) {
      setState(() => _imageUrls = merged);
    }
  }

  static int? _restockQuantityIfMissing(Map<String, dynamic> row) {
    final status = row['status']?.toString().trim();
    if (status == 'hidden') return null;

    final raw = row['stock_quantity'];
    if (raw == null) return 1;
    if (raw is num) {
      return raw.toInt() <= 0 ? 1 : null;
    }
    final parsed = int.tryParse(raw.toString().trim());
    if (parsed == null) return 1;
    return parsed <= 0 ? 1 : null;
  }

  Future<void> _requestSubmit({required bool asDraft}) async {
    if (_saving) return;
    if (!_isEditMode && _lastSavedSnapshot != null) {
      final current = _ManualFormSnapshot.fromState(this);
      if (current == _lastSavedSnapshot) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Повторное сохранение'),
            content: const Text(
              'Вы уже сохраняли данный товар, сохранить ещё раз?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Нет'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Да'),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }
    }
    await _submit(asDraft: asDraft);
  }

  Future<void> _refreshGalleryAfterSave(String sku) async {
    try {
      final media = await widget.database.fetchProductMediaFieldsBySku(sku);
      if (!mounted || media == null) return;
      final urls = productGalleryImageUrls(media);
      if (urls.isEmpty) return;
      setState(() => _imageUrls = List<String>.from(urls));
    } catch (_) {}
  }

  void _onSaveSucceeded({required bool asDraft, required String sku}) {
    _sessionSaveCount++;
    _lastSavedSnapshot = _ManualFormSnapshot.fromState(this);
    _saveBannerPulse++;
    _saveBannerMessage = asDraft
        ? '✓ Товар сохранён в черновики (добавлено за сессию: $_sessionSaveCount)'
        : '✓ Товар добавлен на витрину (добавлено за сессию: $_sessionSaveCount)';
  }

  Future<void> _submit({required bool asDraft}) async {
    final sku = _skuController.text.trim();
    final weight = double.tryParse(_weightController.text.replaceAll(',', '.'));
    final productName = _resolvedProductDisplayName;
    final productCategory = _resolvedProductCategory;

    if (productName.isEmpty) {
      _snack('Укажите наименование изделия', error: true);
      return;
    }
    if (_showCustomSubtypeField &&
        _customSubtypeController.text.trim().isEmpty) {
      _snack('Укажите свой вид изделия', error: true);
      return;
    }
    if (sku.isEmpty || weight == null || weight <= 0) {
      _snack('Укажите SKU и вес (г)', error: true);
      return;
    }
    final price = int.tryParse(_priceController.text.replaceAll(RegExp(r'[^\d]'), ''));
    if (price == null || price <= 0) {
      _snack('Укажите цену продажи (₩) больше 0', error: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final size = double.tryParse(_sizeController.text.replaceAll(',', '.'));
      final notes = _notesController.text.trim();
      final manufacturer = _resolvedManufacturer;

      final ok = _isEditMode
          ? await widget.database.updateManualProduct(
              productId: widget.editProduct!['id']?.toString() ?? '',
              sku: sku,
              name: productName,
              productCategory: productCategory,
              metalType: _resolvedMetalType,
              weightGrams: weight,
              price: price,
              sizeValue: size,
              gemInserts: formatGemInsertsForStorage(
                catalog: _selectedCatalogGems,
                legacy: _legacyGemValues,
              ),
              notes: notes,
              manufacturer: manufacturer,
              stockQuantity: _restockQuantityIfMissing(widget.editProduct!),
              storeLocation: _storeLocationCode,
            )
          : await widget.database.insertManualProduct(
              sku: sku,
              name: productName,
              productCategory: productCategory,
              metalType: _resolvedMetalType,
              weightGrams: weight,
              price: price,
              sizeValue: size,
              gemInserts: formatGemInsertsForStorage(
                catalog: _selectedCatalogGems,
                legacy: _legacyGemValues,
              ),
              notes: notes,
              isDraft: asDraft,
              manufacturer: manufacturer,
              storeLocation: _storeLocationCode,
            );

      if (!ok) {
        _snack(
          _isEditMode
              ? 'Не удалось обновить карточку'
              : (asDraft
                  ? 'Не удалось сохранить в черновики'
                  : 'Не удалось добавить товар'),
          error: true,
        );
        return;
      }

      if (!_isEditMode && !asDraft) {
        _safeFireAndForgetLabelPrintAfterManualSave(sku);
      }

      if (_isEditMode) {
        final productId = widget.editProduct!['id']?.toString().trim() ?? '';
        final galleryOk = await widget.database.updateProductGalleryByProductId(
          productId: productId,
          additionalImages: _imageUrls,
        );
        if (!galleryOk) {
          _snack('Карточка сохранена, но галерея фото не обновилась', error: true);
        }
      }

      if (!_isEditMode) {
        await _attachGalleryForNewManualProduct(sku);
      } else if (_deferredPhotos.isNotEmpty) {
        await _uploadDeferredPhotos(sku);
        setState(() => _deferredPhotos.clear());
        await _refreshGalleryAfterSave(sku);
      }

      await widget.onSaved(asDraft: asDraft);
      if (!mounted) return;

      if (!_isEditMode) {
        setState(() => _onSaveSucceeded(asDraft: asDraft, sku: sku));
        if (_keepFieldsAfterSave) return;
      }

      Navigator.pop(context);
    } catch (error) {
      _snack('Ошибка: $error', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.saleRed : AppColors.primary,
      ),
    );
  }

  void _safeFireAndForgetLabelPrintAfterManualSave(String sku) {
    Future.microtask(() async {
      try {
        final row = await widget.database.fetchProductRowForLabelBySku(sku);
        if (row == null) {
          debugPrint(
            '_ManualProductDialog: label print skipped, row not found for $sku',
          );
          return;
        }
        final data = JewelryLabelData.fromProductMap(row);
        const labelService = LabelPrintService(
          protocol: LabelPrinterProtocol.tspl,
        );
        await labelService.printLabel(data);
        await printJewelryLabelPlatform(
          data,
          labelPrintService: labelService,
        );
      } catch (error, stackTrace) {
        debugPrint(
          'Тихая ошибка печати после ручного сохранения ($sku): $error',
        );
        debugPrint('$stackTrace');
      }
    });
  }

  Widget _buildManualPhotoGrid() {
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: List.generate(ProductItem.maxGalleryImages, (index) {
        if (index < _imageUrls.length) {
          return _ManualDialogPhotoSlot(
            url: _imageUrls[index],
            onRemove: () => _confirmRemoveNetworkPhoto(index),
          );
        }
        final deferredIndex = index - _imageUrls.length;
        if (deferredIndex < _deferredPhotos.length) {
          return _ManualDialogPhotoSlot(
            deferredFile: _deferredPhotos[deferredIndex],
            onRemove: () => _confirmRemoveDeferredPhoto(deferredIndex),
          );
        }
        return const _ManualDialogPhotoSlot();
      }),
    );
  }

  Widget _buildFormFields() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
                Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    label: const Text('Проба 585'),
                    onPressed: _applyProbe585,
                  ),
                  ActionChip(
                    label: const Text('Проба 925'),
                    onPressed: _applyProbe925,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'gold', label: Text('Золото')),
                  ButtonSegment(value: 'silver', label: Text('Серебро')),
                ],
                selected: {_metalCategory},
                onSelectionChanged: (value) {
                  final next = value.first;
                  setState(() => _metalCategory = next);
                  unawaited(_persistLastSelectedMetalCategory(next));
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _metalCategory == 'gold' ? _goldType : _silverType,
                decoration: const InputDecoration(
                  labelText: 'Тип металла',
                  border: OutlineInputBorder(),
                ),
                items: _metalDropdownOptions
                    .map(
                      (item) => DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    if (_metalCategory == 'gold') {
                      _goldType = value;
                    } else {
                      _silverType = value;
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _manufacturerCategory,
                decoration: const InputDecoration(
                  labelText: 'Производитель',
                  border: OutlineInputBorder(),
                ),
                items: _manufacturerOptions
                    .map(
                      (item) => DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _manufacturerCategory = value);
                },
              ),
              if (_manufacturerCategory == 'Другое') ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _customManufacturerController,
                  decoration: const InputDecoration(
                    labelText: 'Своё наименование производителя',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Магазин',
                style: AppTypography.productMeta().copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: StoreLocationCode.icn,
                    label: Text('Инчхон'),
                  ),
                  ButtonSegment(
                    value: StoreLocationCode.ans,
                    label: Text('Ансан'),
                  ),
                ],
                selected: {_storeLocationCode},
                onSelectionChanged: (value) {
                  final next = value.first;
                  setState(() => _storeLocationCode = next);
                  unawaited(_persistLastSelectedStoreLocation(next));
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _productTypeCategory,
                decoration: const InputDecoration(
                  labelText: 'Категория изделия',
                  border: OutlineInputBorder(),
                ),
                items: kJewelryMainCategories
                    .map(
                      (item) => DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _productTypeCategory = value;
                    _subtypeDropdown = kJewelrySubtypeUnspecified;
                    _customSubtypeController.clear();
                  });
                },
              ),
              if (_showSubtypePicker) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: _subtypeDropdown,
                  decoration: const InputDecoration(
                    labelText: 'Вид изделия',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: kJewelrySubtypeUnspecified,
                      child: Text('Не указан'),
                    ),
                    ...?kJewelryCategorySubtypes[_productTypeCategory]
                        ?.map(
                          (subtype) => DropdownMenuItem(
                            value: subtype,
                            child: Text(subtype),
                          ),
                        ),
                    const DropdownMenuItem(
                      value: kJewelrySubtypeCustom,
                      child: Text('Свой вариант...'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _subtypeDropdown = value;
                      if (value != kJewelrySubtypeCustom) {
                        _customSubtypeController.clear();
                      }
                    });
                  },
                ),
              ],
              if (_showCustomSubtypeField) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _customSubtypeController,
                  decoration: InputDecoration(
                    labelText: 'Свой вид изделия',
                    hintText: _customSubtypeHint,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              if (_productTypeCategory == kJewelryCategoryOther) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _customNameController,
                  decoration: const InputDecoration(
                    labelText: 'Своё наименование',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _skuController,
                      readOnly: _isEditMode,
                      decoration: InputDecoration(
                        labelText: 'SKU / артикул',
                        border: const OutlineInputBorder(),
                        filled: _isEditMode,
                        helperText: _isEditMode
                            ? 'SKU нельзя менять (ключ карточки)'
                            : null,
                      ),
                    ),
                  ),
                  if (!_isEditMode) ...[
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: OutlinedButton.icon(
                        onPressed: (_saving || _skuPhotoLookupInProgress)
                            ? null
                            : _lookupPhotosBySku,
                        icon: _skuPhotoLookupInProgress
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(
                                Icons.image_search_outlined,
                                size: 20,
                              ),
                        label: const Text('Найти фото'),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _weightController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Вес, г',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _sizeController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Размер',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _gemController,
                readOnly: true,
                onTap: _saving ? null : _openGemInsertsPicker,
                decoration: InputDecoration(
                  labelText: 'Вставки',
                  hintText: 'Выберите вставки',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    tooltip: 'Выбрать вставки',
                    onPressed: _saving ? null : _openGemInsertsPicker,
                    icon: const Icon(Icons.checklist_rounded),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _priceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Цена продажи (₩)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Фото (до ${ProductItem.maxGalleryImages})',
                style: AppTypography.heading(fontSize: 15),
              ),
              const SizedBox(height: 8),
              _buildManualPhotoGrid(),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _saving ? null : _pickPhoto,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(
                  'Добавить фото ($_totalPhotoCount/${ProductItem.maxGalleryImages})',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _notesController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Описание (notes)',
                  border: OutlineInputBorder(),
                  helperText: 'Заметки администратора; наименование — в категории выше',
                ),
              ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final dialogHeight =
        (MediaQuery.sizeOf(context).height * 0.86).clamp(420.0, 720.0);

    return AlertDialog(
      title: Text(
        _isEditMode ? 'Редактировать карточку' : 'Добавить товар',
        style: AppTypography.heading(fontSize: 18),
      ),
      content: SizedBox(
        width: 520,
        height: dialogHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_photoLookupMessage != null)
              _ManualInlineNotice(
                message: _photoLookupMessage!,
                pulse: _photoLookupPulse,
                success: _photoLookupSuccess,
              ),
            if (!_isEditMode && _saveBannerMessage != null)
              _ManualSaveBanner(
                message: _saveBannerMessage!,
                pulse: _saveBannerPulse,
              ),
            Expanded(
              child: Scrollbar(
                thumbVisibility: true,
                child: SingleChildScrollView(
                  primary: false,
                  padding: const EdgeInsets.only(top: 4, right: 14),
                  child: _buildFormFields(),
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            if (!_isEditMode)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                visualDensity: VisualDensity.compact,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(
                  'Не очищать поля после сохранения',
                  style: AppTypography.productMeta(),
                ),
                value: _keepFieldsAfterSave,
                onChanged: _saving
                    ? null
                    : (value) =>
                        setState(() => _keepFieldsAfterSave = value ?? false),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Закрыть'),
                  ),
                  if (!_isEditMode) ...[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed:
                          _saving ? null : () => _requestSubmit(asDraft: true),
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Сохранить в черновики'),
                    ),
                  ],
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed:
                        _saving ? null : () => _requestSubmit(asDraft: false),
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _isEditMode ? 'Сохранить' : 'Добавить на витрину',
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManualDialogPhotoSlot extends StatelessWidget {
  const _ManualDialogPhotoSlot({
    this.url,
    this.deferredFile,
    this.onRemove,
  });

  final String? url;
  final XFile? deferredFile;
  final VoidCallback? onRemove;

  bool get _hasPhoto =>
      (url != null && url!.isNotEmpty) || deferredFile != null;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: !_hasPhoto
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.image_not_supported_outlined,
                          color: AppColors.textSecondary.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 4),
                        Text('Нет фото', style: AppTypography.productMeta()),
                      ],
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: url != null && url!.isNotEmpty
                          ? Image.network(
                              url!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.broken_image_outlined),
                            )
                          : _DeferredPhotoPreview(file: deferredFile!),
                    ),
            ),
          ),
          if (_hasPhoto && onRemove != null)
            Positioned(
              top: 6,
              right: 6,
              child: Material(
                color: AppColors.saleRed,
                elevation: 2,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onRemove,
                  customBorder: const CircleBorder(),
                  child: const SizedBox(
                    width: 28,
                    height: 28,
                    child: Icon(
                      Icons.close,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DeferredPhotoPreview extends StatelessWidget {
  const _DeferredPhotoPreview({required this.file});

  final XFile file;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: file.readAsBytes(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        }
        return Image.memory(
          snapshot.data!,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
        );
      },
    );
  }
}
