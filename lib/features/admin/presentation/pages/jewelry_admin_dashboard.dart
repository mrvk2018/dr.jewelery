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
import '../../../../core/utils/round_krw_up_1000.dart';
import '../../../../core/widgets/krw_text.dart';
import '../../../../shared/providers/profile_scope.dart';
import '../../application/pos_cart_controller.dart';
import '../widgets/admin_pos_cart_sheet.dart';
import '../widgets/admin_product_photo_preview.dart';
import '../../../../shared/models/product_item.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../catalog/presentation/widgets/smart_filter_widget.dart';
import '../../../printing/domain/jewelry_label_data.dart';
import '../../../printing/infrastructure/browser_label_print.dart';
import '../../../printing/presentation/widgets/jewelry_label_preview.dart';
import '../../../printing/presentation/widgets/product_return_dialog.dart';
import '../../../../core/utils/product_gallery_urls.dart';
import '../../../../core/utils/product_size_utils.dart';
import '../../../../core/utils/store_location_utils.dart';
import '../../data/admin_manual_product_storage.dart';
import '../screens/draft_intake_screen.dart';
import '../../data/scrap_metal_storage.dart';
import '../screens/scrap_metal_intake_screen.dart';

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

String adminShowroomSalePriceLabel(Map<String, dynamic> row) {
  final krw = adminShowroomSalePriceKrw(row);
  if (krw == null) return '—';
  return formatWon(krw);
}

String adminShowroomKrwLabel(int krw) => formatWon(krw);

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

/// Десктопный рабочий стол «Доктор Ювелирка»: витрина + медиа + KPI.
class JewelryAdminDashboard extends StatefulWidget {
  JewelryAdminDashboard({
    super.key,
    DatabaseService? database,
    this.onPosSaleArchived,
    this.onProductTransfersChanged,
    this.sellerStaffMode = false,
    this.presetSellerPromoCode,
    this.presetSellerName,
  }) : database = database ?? DatabaseService.create();

  final DatabaseService database;
  final VoidCallback? onPosSaleArchived;
  final VoidCallback? onProductTransfersChanged;
  final bool sellerStaffMode;
  final String? presetSellerPromoCode;
  final String? presetSellerName;

  @override
  State<JewelryAdminDashboard> createState() => JewelryAdminDashboardState();
}

class JewelryAdminDashboardState extends State<JewelryAdminDashboard> {
  /// Обновить каталог после возврата с другой вкладки (История продаж).
  Future<void> refreshCatalog() => _refreshCatalog();
  final PosCartController _posCart = PosCartController();

  List<Map<String, dynamic>> _products = const [];
  Map<String, dynamic>? _selected;
  bool _initialLoading = true;

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
    if (_catalogStatus(row) == 'in_transfer') return false;
    return _stockQty(row) > 0;
  }

  String get _transferActorCode =>
      widget.presetSellerPromoCode?.trim().toUpperCase() ?? 'ADMIN';

  String _cell(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value == null) return '—';
    final text = value.toString().trim();
    return text.isEmpty ? '—' : text;
  }

  static String? _productId(Map<String, dynamic>? row) {
    if (row == null) return null;
    final id = row['id']?.toString().trim();
    if (id == null || id.isEmpty) return null;
    return id;
  }

  double _weight(Map<String, dynamic> row) {
    return (row['weight_grams'] as num?)?.toDouble() ?? 0;
  }

  double _size(Map<String, dynamic> row) => productDisplaySizeFromRow(row);

  List<String?> _gallerySlots(Map<String, dynamic> row) =>
      productGallerySlotsFromRow(row);

  void _applyGallerySlotsToCatalogBySku(
    String sku,
    List<String?> slots,
  ) {
    final needle = normalizeProductSku(sku);
    if (needle.isEmpty) return;
    final vitrine = productGalleryVitrineUrlsFromSlots(slots);
    final fields = productGalleryDbFieldsFromUrls(vitrine);
    final slotsJson = productGallerySlotsToRpcJson(slots);
    setState(() {
      _products = _products.map((row) {
        if (normalizeProductSku(_cell(row, 'sku')) != needle) return row;
        return Map<String, dynamic>.from(row)
          ..['gallery_slots'] = slotsJson
          ..['image_url'] = fields['image_url']
          ..['images'] = fields['images']
          ..['additional_images'] = fields['additional_images'];
      }).toList();
      final sel = _selected;
      if (sel != null && normalizeProductSku(_cell(sel, 'sku')) == needle) {
        _selected = Map<String, dynamic>.from(sel)
          ..['gallery_slots'] = slotsJson
          ..['image_url'] = fields['image_url']
          ..['images'] = fields['images']
          ..['additional_images'] = fields['additional_images'];
      }
    });
  }

  List<String> _imageUrls(Map<String, dynamic> row) =>
      productGalleryImageUrls(row);

  String? _thumbnailUrlForRow(Map<String, dynamic> row) {
    return productGalleryPrimaryUrlFromSlots(_gallerySlots(row)) ??
        (_imageUrls(row).isEmpty ? null : _imageUrls(row).first);
  }

  Future<void> _fetchAndMergeProductMedia({
    required String productId,
  }) async {
    if (productId.isEmpty) return;

    try {
      final media =
          await widget.database.fetchProductMediaFieldsByProductId(productId);
      if (!mounted || media == null) return;

      final selected = _selected;
      if (selected == null) return;
      if (_productId(selected) != productId) return;

      setState(() {
        _selected = Map<String, dynamic>.from(selected)
          ..['gallery_slots'] = media['gallery_slots']
          ..['additional_images'] = media['additional_images']
          ..['image_url'] = media['image_url'];
      });
    } catch (error, stackTrace) {
      debugPrint('JewelryAdminDashboard._fetchAndMergeProductMedia: $error');
      debugPrint('$stackTrace');
    }
  }

  Future<void> _selectProductRow(Map<String, dynamic> row) async {
    final productId = _productId(row);
    setState(() => _selected = row);
    if (productId != null) {
      await _fetchAndMergeProductMedia(productId: productId);
    }
  }

  Future<void> _openSelectedPhotoPreview(int slotIndex) async {
    final row = _selected;
    if (row == null) return;
    final slots = _gallerySlots(row);
    if (slotIndex < 0 || slotIndex >= slots.length) return;
    final urls = productGalleryVitrineUrlsFromSlots(slots);
    final tapped = slots[slotIndex]?.trim();
    if (tapped == null || tapped.isEmpty) return;
    final index = urls.indexOf(tapped);
    if (index < 0) return;
    final sku = _cell(row, 'sku');
    final subtitle =
        '${_weight(row).toStringAsFixed(2)} г · ${storeLocationDisplayLabelForRow(row)}';
    await showAdminProductPhotoPreview(
      context,
      title: sku,
      subtitle: subtitle,
      imageUrls: urls,
      initialIndex: index,
    );
  }

  void _applyRows(List<Map<String, dynamic>> rows) {
    final active = rows.where(_isShowroomRow).toList();
    Map<String, dynamic>? selected = _selected;
    final previousId = _productId(selected);
    if (previousId != null) {
      selected = null;
      for (final row in active) {
        if (_productId(row) == previousId) {
          selected = row;
          break;
        }
      }
    }
    setState(() {
      _products = active;
      _selected = selected;
    });
    final selectedId = _productId(selected);
    if (selectedId != null) {
      unawaited(_fetchAndMergeProductMedia(productId: selectedId));
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
        builder: (_) => DraftIntakeScreen(
          database: widget.database,
          onTransfersMutated: widget.onProductTransfersChanged,
        ),
      ),
    );
    if (!mounted) return;
    await _refreshCatalog();
  }

  Future<void> _openScrapIntake() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ScrapMetalIntakeScreen(database: widget.database),
      ),
    );
  }

  Future<void> _openSellerScrapIntake() async {
    final code = widget.presetSellerPromoCode?.trim().toUpperCase();
    final name = widget.presetSellerName?.trim();
    if (code == null || code.isEmpty) {
      _snack('Смена продавца не задана', error: true);
      return;
    }
    final storage = await ScrapMetalStorage.create();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ScrapMetalIntakeScreen(
          database: widget.database,
          initialSellerCode: code,
          initialSellerName: name?.isNotEmpty == true ? name : code,
          initialStoreLocation: storage.storeLocation,
          hideJournalBulkWriteOff: true,
          actorCode: code,
        ),
      ),
    );
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
        onGallerySlotsSynced: _applyGallerySlotsToCatalogBySku,
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
    final productId = _productId(row);
    if (productId == null) {
      _snack('У позиции нет id', error: true);
      return;
    }
    final sku = _cell(row, 'sku');
    final weightRaw = row['weight_grams'];
    final weight = weightRaw is num
        ? weightRaw.toDouble()
        : double.tryParse('$weightRaw');
    final weightLabel =
        weight != null ? '${weight.toStringAsFixed(2)} г' : '—';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Вы точно хотите безвозвратно удалить?'),
        content: Text(
          'SKU $sku · $weightLabel\n\n'
          'Изделие будет полностью удалено из базы (public.products), '
          'минуя черновики и архив. Это действие нельзя отменить. '
          'Если по изделию есть продажи в истории кассы — удаление будет заблокировано.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.saleRed),
            child: const Text('Удалить безвозвратно'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final result = await widget.database.deleteProductPermanently(productId);
      if (!result.ok) {
        _snack(result.error ?? 'Удаление не выполнено', error: true);
        return;
      }
      if (_posCart.containsProduct(productId)) {
        _posCart.removeFromCart(productId);
      }
      setState(() => _selected = null);
      widget.onProductTransfersChanged?.call();
      _snack('Изделие $sku удалено из базы');
      await _refreshCatalog();
    } catch (error) {
      _snack('Ошибка удаления: $error', error: true);
    }
  }

  Future<void> _addSelectedToPosCart() async {
    final row = _selected;
    if (row == null) {
      _snack('Выберите товар в таблице', error: true);
      return;
    }
    if (_catalogStatus(row) == 'in_transfer') {
      _snack(
        'Товар находится в трансфере и недоступен для продажи',
        error: true,
      );
      return;
    }
    final currentRow = _selected ?? row;
    final productId = _productId(currentRow);
    if (productId != null) {
      await _fetchAndMergeProductMedia(productId: productId);
    }
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
        lockSellerSelection: widget.sellerStaffMode,
        presetSellerPromoCode: widget.presetSellerPromoCode,
        presetSellerName: widget.presetSellerName,
        onArchived: () async {
          _posCart.clearCart();
          await _refreshCatalog();
          widget.onPosSaleArchived?.call();
        },
      ),
    );
  }

  Future<void> _startProductTransfer() async {
    final row = _selected;
    if (row == null) {
      _snack('Выберите товар в таблице', error: true);
      return;
    }
    final productId = _productId(row);
    if (productId == null) {
      _snack('У позиции нет id', error: true);
      return;
    }
    if (_catalogStatus(row) == 'in_transfer') {
      _snack('Товар уже в трансфере', error: true);
      return;
    }
    final from = row['store_location']?.toString().trim().toUpperCase();
    var defaultTo = 'ANS';
    if (from == 'ICN') {
      defaultTo = 'ANS';
    } else if (from == 'ANS') {
      defaultTo = 'ICN';
    }

    final notesController = TextEditingController();
    var toStore = defaultTo;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('В трансфер'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'SKU ${_cell(row, 'sku')} · ${from ?? '—'} →',
                style: AppTypography.productMeta(),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: toStore,
                decoration: const InputDecoration(
                  labelText: 'Магазин-получатель',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'ICN', child: Text('Инчхон (ICN)')),
                  DropdownMenuItem(value: 'ANS', child: Text('Ансан (ANS)')),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setLocal(() => toStore = v);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Комментарий (необязательно)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Отправить'),
            ),
          ],
        ),
      ),
    );

    final notesText = notesController.text.trim();
    notesController.dispose();

    if (confirmed != true || !mounted) return;

    try {
      final result = await widget.database.createProductTransferById(
        productId: productId,
        toStore: toStore,
        senderCode: _transferActorCode,
        notes: notesText.isEmpty ? null : notesText,
      );
      if (result['ok'] != true) {
        _snack(result['error']?.toString() ?? 'Трансфер не создан', error: true);
        return;
      }
      _snack('Отправлено в $toStore');
      widget.onProductTransfersChanged?.call();
      setState(() => _selected = null);
      await _refreshCatalog();
    } catch (error) {
      _snack('Ошибка трансфера: $error', error: true);
    }
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
      await printJewelryLabelPlatform(labelData);
      if (!mounted) return;
      _snack('Откройте диалог печати и выберите принтер (TSC TE310, 60×12 mm)');
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
    final panelAdmin = isSuperAdmin && !widget.sellerStaffMode;
    final selectedProductId = _productId(_selected);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: _initialLoading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                final lowViewport = constraints.maxHeight < 700;
                final tableMinHeight = lowViewport ? 300.0 : 260.0;

                final columnChildren = <Widget>[
                  _TopControlBar(
                    isSuperAdmin: panelAdmin,
                    showSellerQuickActions: widget.sellerStaffMode,
                    onOpenDraft: _openDraftIntake,
                    onOpenScrap: widget.sellerStaffMode
                        ? _openSellerScrapIntake
                        : _openScrapIntake,
                    onAddProduct: _openAddProductDialog,
                    onProductReturn: _openProductReturnDialog,
                  ),
                  const SizedBox(height: 8),
                  SmartFilterWidget(
                    database: widget.database,
                    compactAdminLayout: true,
                    onFilterApplied: _applyRows,
                  ),
                  const SizedBox(height: 8),
                  _ShowroomKpiStrip(
                    totalCount: _products.length,
                    totalWeightGrams: _totalWeightGrams,
                    totalPriceKrw: _totalPriceKrw,
                    storeStats: _storeSelectionStats,
                  ),
                  const SizedBox(height: 8),
                  if (!lowViewport)
                    Expanded(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: tableMinHeight),
                        child: _ProductTablePanel(
                          products: _products,
                          selectedProductId: selectedProductId,
                          isSuperAdmin: panelAdmin,
                          onSelect: _selectProductRow,
                          onEdit: _openEditProductDialog,
                          cell: _cell,
                          insertLabel: adminProductInsertLabel,
                          productName: extractStoredProductName,
                          salePriceLabel: adminShowroomSalePriceLabel,
                          weight: _weight,
                          size: _size,
                          thumbnailUrl: _thumbnailUrlForRow,
                        ),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: tableMinHeight,
                        maxHeight: tableMinHeight,
                      ),
                      child: _ProductTablePanel(
                        products: _products,
                        selectedProductId: selectedProductId,
                        isSuperAdmin: panelAdmin,
                        onSelect: _selectProductRow,
                        onEdit: _openEditProductDialog,
                        cell: _cell,
                        insertLabel: adminProductInsertLabel,
                        productName: extractStoredProductName,
                        salePriceLabel: adminShowroomSalePriceLabel,
                        weight: _weight,
                        size: _size,
                        thumbnailUrl: _thumbnailUrlForRow,
                      ),
                    ),
                  if (_selected != null) ...[
                    const SizedBox(height: 8),
                    _SelectedProductMediaBar(
                      selected: _selected!,
                      gallerySlots: _gallerySlots(_selected!),
                      cell: _cell,
                      weight: _weight,
                      onPhotoTap: _openSelectedPhotoPreview,
                    ),
                  ],
                  const SizedBox(height: 8),
                  _BottomActionBar(
                    hasSelection: _selected != null,
                    isSuperAdmin: panelAdmin,
                    posCartCount: _posCart.lineCount,
                    onAddToPosCart: _addSelectedToPosCart,
                    onOpenPosCart: _openPosCartSheet,
                    onPrint: _printDuplicateLabel,
                    onEdit: _editSelectedCard,
                    onMarkSold: _markSoldSelected,
                    onWriteOff: _writeOffSelected,
                    onTransfer: _startProductTransfer,
                  ),
                ];

                final padded = Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: lowViewport
                      ? SingleChildScrollView(
                          child: ConstrainedBox(
                            constraints: BoxConstraints(
                              minHeight: constraints.maxHeight - 20,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: columnChildren,
                            ),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: columnChildren,
                        ),
                );

                return padded;
              },
            ),
    );
  }
}

class _TopControlBar extends StatelessWidget {
  const _TopControlBar({
    required this.isSuperAdmin,
    required this.showSellerQuickActions,
    required this.onOpenDraft,
    required this.onOpenScrap,
    required this.onAddProduct,
    required this.onProductReturn,
  });

  final bool isSuperAdmin;
  final bool showSellerQuickActions;
  final VoidCallback onOpenDraft;
  final VoidCallback onOpenScrap;
  final VoidCallback onAddProduct;
  final VoidCallback onProductReturn;

  static final _compactBtnStyle = ButtonStyle(
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
    minimumSize: const WidgetStatePropertyAll(Size(0, 32)),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
    textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12)),
  );

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              if (isSuperAdmin) ...[
                OutlinedButton.icon(
                  onPressed: onOpenDraft,
                  style: _compactBtnStyle,
                  icon: const Icon(Icons.move_to_inbox_outlined, size: 16),
                  label: const Text('Приёмка черновиков'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onOpenScrap,
                  style: _compactBtnStyle,
                  icon: const Icon(Icons.scale_outlined, size: 16),
                  label: const Text('Приёмка лома'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: onAddProduct,
                  style: _compactBtnStyle.copyWith(
                    backgroundColor:
                        const WidgetStatePropertyAll(AppColors.primary),
                    foregroundColor:
                        const WidgetStatePropertyAll(AppColors.textOnPrimary),
                  ),
                  icon: const Icon(Icons.add_circle_outline, size: 16),
                  label: const Text('Добавить товар'),
                ),
                const SizedBox(width: 8),
              ],
              if (isSuperAdmin)
                OutlinedButton.icon(
                  onPressed: onProductReturn,
                  style: _compactBtnStyle,
                  icon: const Icon(Icons.replay_outlined, size: 16),
                  label: const Text('Возврат товара'),
                ),
              if (showSellerQuickActions) ...[
                OutlinedButton.icon(
                  onPressed: onOpenScrap,
                  style: _compactBtnStyle,
                  icon: const Icon(Icons.scale_outlined, size: 16),
                  label: const Text('Приёмка лома'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: onProductReturn,
                  style: _compactBtnStyle,
                  icon: const Icon(Icons.replay_outlined, size: 16),
                  label: const Text('Возврат товара'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProductTablePanel extends StatefulWidget {
  const _ProductTablePanel({
    required this.products,
    required this.selectedProductId,
    required this.isSuperAdmin,
    required this.onSelect,
    required this.onEdit,
    required this.cell,
    required this.insertLabel,
    required this.productName,
    required this.salePriceLabel,
    required this.weight,
    required this.size,
    required this.thumbnailUrl,
  });

  final List<Map<String, dynamic>> products;
  final String? selectedProductId;
  final bool isSuperAdmin;
  final ValueChanged<Map<String, dynamic>> onSelect;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final String Function(Map<String, dynamic>, String) cell;
  final String Function(Map<String, dynamic>) insertLabel;
  final String Function(Map<String, dynamic>) productName;
  final String Function(Map<String, dynamic>) salePriceLabel;
  final double Function(Map<String, dynamic>) weight;
  final double Function(Map<String, dynamic>) size;
  final String? Function(Map<String, dynamic>) thumbnailUrl;

  @override
  State<_ProductTablePanel> createState() => _ProductTablePanelState();
}

class _ProductTablePanelState extends State<_ProductTablePanel> {
  final ScrollController _verticalScroll = ScrollController();

  static const _rowHeight = 44.0;
  static const _headerHeight = 38.0;

  /// Доли ширины таблицы (сумма ≈ 1.0).
  static const _colFlex = <double>[
    0.06, // фото
    0.11, // sku
    0.08, // магазин
    0.09, // металл
    0.07, // вес
    0.07, // размер
    0.14, // вставки
    0.09, // цена
    0.21, // описание
    0.08, // действие
  ];

  static const _headers = <String>[
    'Фото',
    'Артикул',
    'Магазин',
    'Металл',
    'Вес, г',
    'Размер',
    'Вставки',
    'Цена',
    'Описание',
    '',
  ];

  @override
  void dispose() {
    _verticalScroll.dispose();
    super.dispose();
  }

  List<double> _columnWidths(double tableWidth) {
  final horizontalPad = 16.0;
  final inner = tableWidth - horizontalPad;
    return _colFlex.map((f) => inner * f).toList();
  }

  Widget _headerCell(String label, double width) {
    return SizedBox(
      width: width,
      child: Text(
        label,
        style: AppTypography.productMeta().copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 11,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _dataCell(String text, double width, {int maxLines = 1}) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        style: AppTypography.productMeta().copyWith(fontSize: 12),
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _priceCell(Map<String, dynamic> row, double width) {
    final krw = adminShowroomSalePriceKrw(row);
    final style = AppTypography.productMeta().copyWith(fontSize: 12);
  return SizedBox(
      width: width,
      child: krw == null
          ? Text('—', style: style)
          : KrwText(amount: krw, style: style, digitStyle: style),
    );
  }

  @override
  Widget build(BuildContext context) {
    final products = widget.products;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border),
      ),
      child: products.isEmpty
          ? Center(
              child: Text(
                'Нет активных позиций (stock_quantity > 0)',
                style: AppTypography.productMeta(),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final widths = _columnWidths(constraints.maxWidth);

                Widget tableHeader() {
                  return Container(
                    height: _headerHeight,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    alignment: Alignment.centerLeft,
                    decoration: const BoxDecoration(
                      color: AppColors.cardBackground,
                      border: Border(
                        bottom: BorderSide(color: AppColors.border),
                      ),
                    ),
                    child: Row(
                      children: [
                        for (var i = 0; i < _headers.length; i++)
                          _headerCell(_headers[i], widths[i]),
                      ],
                    ),
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    tableHeader(),
                    Expanded(
                      child: Scrollbar(
                        controller: _verticalScroll,
                        thumbVisibility: true,
                        child: ListView.builder(
                          controller: _verticalScroll,
                          padding: const EdgeInsets.only(bottom: 4),
                          itemCount: products.length,
                          itemBuilder: (context, index) {
                            final row = products[index];
                            final sku = widget.cell(row, 'sku');
                            final rowId = row['id']?.toString().trim() ?? '';
                            final selected = rowId.isNotEmpty &&
                                rowId == widget.selectedProductId;
                            final thumb = widget.thumbnailUrl(row);

                            return Material(
                              color: selected
                                  ? AppColors.accent.withValues(alpha: 0.1)
                                  : (index.isEven
                                      ? AppColors.background
                                      : AppColors.cardBackground),
                              child: InkWell(
                                onTap: () => widget.onSelect(row),
                                child: SizedBox(
                                  height: _rowHeight,
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.symmetric(horizontal: 8),
                                    child: Row(
                                      children: [
                                        SizedBox(
                                          width: widths[0],
                                          child: _TableThumb(url: thumb),
                                        ),
                                        _dataCell(sku, widths[1]),
                                        SizedBox(
                                          width: widths[2],
                                          child: _StoreLocationBadge(row: row),
                                        ),
                                        _dataCell(
                                          widget.cell(row, 'metal'),
                                          widths[3],
                                        ),
                                        _dataCell(
                                          widget
                                              .weight(row)
                                              .toStringAsFixed(2),
                                          widths[4],
                                        ),
                                        _dataCell(
                                          widget.size(row).toStringAsFixed(2),
                                          widths[5],
                                        ),
                                        _dataCell(
                                          widget.insertLabel(row),
                                          widths[6],
                                          maxLines: 2,
                                        ),
                                        _priceCell(row, widths[7]),
                                        _dataCell(
                                          widget.productName(row),
                                          widths[8],
                                          maxLines: 2,
                                        ),
                                        SizedBox(
                                          width: widths[9],
                                          child: widget.isSuperAdmin
                                              ? IconButton(
                                                  tooltip: 'Редактировать',
                                                  padding: EdgeInsets.zero,
                                                  constraints:
                                                      const BoxConstraints(
                                                    minWidth: 32,
                                                    minHeight: 32,
                                                  ),
                                                  onPressed: () =>
                                                      widget.onEdit(row),
                                                  icon: const Icon(
                                                    Icons.edit_outlined,
                                                    size: 18,
                                                  ),
                                                )
                                              : const SizedBox.shrink(),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

class _TableThumb extends StatelessWidget {
  const _TableThumb({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: AppColors.border),
          color: AppColors.cardBackground,
        ),
        child: url == null
            ? Icon(
                Icons.image_outlined,
                size: 18,
                color: AppColors.textSecondary.withValues(alpha: 0.5),
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  url!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.broken_image_outlined, size: 18),
                ),
              ),
      ),
    );
  }
}

class _ShowroomKpiStrip extends StatelessWidget {
  const _ShowroomKpiStrip({
    required this.totalCount,
    required this.totalWeightGrams,
    required this.totalPriceKrw,
    required this.storeStats,
  });

  final int totalCount;
  final double totalWeightGrams;
  final int totalPriceKrw;
  final Map<String, ShowroomStoreSelectionStats> storeStats;

  String _storeLine(String code, String title) {
    final stats = storeStats[code] ?? const ShowroomStoreSelectionStats();
    return '$title ${stats.count} шт · '
        '${stats.weightGrams.toStringAsFixed(1)} г · '
        '${adminShowroomKrwLabel(stats.priceKrw)}';
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 900;
            final kpiRow = Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _KpiCompactChip(
                  label: 'Позиций',
                  value: '$totalCount',
                ),
                _KpiCompactChip(
                  label: 'Масса',
                  value: '${totalWeightGrams.toStringAsFixed(2)} г',
                ),
                _KpiAmountChip(label: 'Сумма', amountKrw: totalPriceKrw),
                Container(
                  width: 1,
                  height: 28,
                  color: AppColors.border,
                ),
                Text(
                  _storeLine(StoreLocationCode.icn, 'Инчхон:'),
                  style: AppTypography.productMeta().copyWith(fontSize: 11),
                ),
                Text(
                  _storeLine(StoreLocationCode.ans, 'Ансан:'),
                  style: AppTypography.productMeta().copyWith(fontSize: 11),
                ),
              ],
            );

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'KPI витрины (текущая выборка)',
                  style: AppTypography.heading(fontSize: 13),
                ),
                const SizedBox(height: 6),
                if (narrow)
                  kpiRow
                else
                  Row(
                    children: [
                      Expanded(child: kpiRow),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _KpiCompactChip extends StatelessWidget {
  const _KpiCompactChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: AppTypography.productMeta().copyWith(fontSize: 11),
          ),
          Text(
            value,
            style: AppTypography.productMeta().copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiAmountChip extends StatelessWidget {
  const _KpiAmountChip({required this.label, required this.amountKrw});

  final String label;
  final int amountKrw;

  @override
  Widget build(BuildContext context) {
    final valueStyle = AppTypography.productMeta().copyWith(
      fontSize: 11,
      fontWeight: FontWeight.w700,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: AppTypography.productMeta().copyWith(fontSize: 11)),
          KrwText(amount: amountKrw, style: valueStyle, digitStyle: valueStyle),
        ],
      ),
    );
  }
}

class _SelectedProductMediaBar extends StatelessWidget {
  const _SelectedProductMediaBar({
    required this.selected,
    required this.gallerySlots,
    required this.cell,
    required this.weight,
    required this.onPhotoTap,
  });

  final Map<String, dynamic> selected;
  final List<String?> gallerySlots;
  final String Function(Map<String, dynamic>, String) cell;
  final double Function(Map<String, dynamic>) weight;
  final ValueChanged<int> onPhotoTap;

  @override
  Widget build(BuildContext context) {
    final sku = cell(selected, 'sku');
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Фото · $sku · ${weight(selected).toStringAsFixed(2)} г · '
                '${storeLocationDisplayLabelForRow(selected)}',
                style: AppTypography.productMeta().copyWith(fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0;
                    index < ProductItem.maxGalleryImages;
                    index++) ...[
                  if (index > 0) const SizedBox(width: 6),
                  _SelectedGallerySlotPreview(
                    label: kProductGallerySlotLabels[index],
                    url: index < gallerySlots.length
                        ? gallerySlots[index]
                        : null,
                    onTap: _slotHasPhoto(gallerySlots, index)
                        ? () => onPhotoTap(index)
                        : null,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  static bool _slotHasPhoto(List<String?> slots, int index) {
    if (index < 0 || index >= slots.length) return false;
    final url = slots[index];
    return url != null && url.trim().isNotEmpty;
  }
}

/// Только просмотр: пустой слот без действия, заполненный — увеличение по клику.
class _SelectedGallerySlotPreview extends StatelessWidget {
  const _SelectedGallerySlotPreview({
    required this.label,
    required this.url,
    this.onTap,
  });

  final String label;
  final String? url;
  final VoidCallback? onTap;

  bool get _filled => url != null && url!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 48,
          height: 48,
          child: _filled
              ? AdminClickableNetworkThumbnail(
                  imageUrl: url,
                  size: 48,
                  onTap: onTap,
                )
              : DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.cardBackground,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const SizedBox.expand(),
                ),
        ),
        const SizedBox(height: 2),
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: AppTypography.productMeta().copyWith(fontSize: 9),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}

class _GallerySlotArrowButton extends StatelessWidget {
  const _GallerySlotArrowButton({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  final String label;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          child: Text(
            label,
            style: AppTypography.productMeta().copyWith(
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.fg.withValues(alpha: 0.25)),
      ),
      child: Text(
        label,
        style: AppTypography.productMeta().copyWith(
          color: colors.fg,
          fontWeight: FontWeight.w700,
          fontSize: 10,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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
    required this.onTransfer,
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
  final VoidCallback onTransfer;

  static const _soldGreen = Color(0xFF1B5E20);

  static final _barBtnStyle = ButtonStyle(
    padding: const WidgetStatePropertyAll(
      EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    ),
    minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
    textStyle: const WidgetStatePropertyAll(
      TextStyle(fontSize: 12, overflow: TextOverflow.ellipsis),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[
      FilledButton.icon(
        onPressed: hasSelection ? onAddToPosCart : null,
        style: _barBtnStyle.copyWith(
          backgroundColor: const WidgetStatePropertyAll(AppColors.accent),
        ),
        icon: const Icon(Icons.add_shopping_cart_outlined, size: 16),
        label: const Text('В POS-корзину'),
      ),
      Badge(
        isLabelVisible: posCartCount > 0,
        label: Text('$posCartCount'),
        child: OutlinedButton.icon(
          onPressed: onOpenPosCart,
          style: _barBtnStyle,
          icon: const Icon(Icons.shopping_cart_checkout_outlined, size: 16),
          label: Text(
            posCartCount > 0 ? 'POS ($posCartCount)' : 'POS-корзина',
          ),
        ),
      ),
      FilledButton.tonalIcon(
        onPressed: hasSelection ? onPrint : null,
        style: _barBtnStyle,
        icon: const Icon(Icons.print_outlined, size: 16),
        label: const Text('Дубликат бирки'),
      ),
      OutlinedButton.icon(
        onPressed: hasSelection ? onTransfer : null,
        style: _barBtnStyle,
        icon: const Icon(Icons.local_shipping_outlined, size: 16),
        label: const Text('В трансфер'),
      ),
      if (isSuperAdmin) ...[
        OutlinedButton.icon(
          onPressed: hasSelection ? onEdit : null,
          style: _barBtnStyle,
          icon: const Icon(Icons.edit_outlined, size: 16),
          label: const Text('Редактировать'),
        ),
        FilledButton.icon(
          onPressed: hasSelection ? onMarkSold : null,
          style: _barBtnStyle.copyWith(
            backgroundColor: const WidgetStatePropertyAll(_soldGreen),
            foregroundColor: const WidgetStatePropertyAll(Colors.white),
          ),
          icon: const Icon(Icons.handshake_outlined, size: 16),
          label: const Text('Продано'),
        ),
        OutlinedButton.icon(
          onPressed: hasSelection ? onWriteOff : null,
          style: _barBtnStyle.copyWith(
            foregroundColor: const WidgetStatePropertyAll(AppColors.saleRed),
            side: const WidgetStatePropertyAll(
              BorderSide(color: AppColors.saleRed),
            ),
          ),
          icon: const Icon(Icons.delete_outline, size: 16),
          label: const Text('Списать'),
        ),
      ],
    ];

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Scrollbar(
          thumbVisibility: true,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < buttons.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  buttons[i],
                ],
              ],
            ),
          ),
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
    final deferredKeys = state._deferredBySlot.entries
        .map((e) => '${e.key}|${e.value.name}|${e.value.hashCode}')
        .toList()
      ..sort();
    final slotUrls = state._gallerySlots
        .map((u) => u?.trim() ?? '')
        .where((u) => u.isNotEmpty)
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
      imageUrls: slotUrls,
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
    this.onGallerySlotsSynced,
    this.editProduct,
    this.catalogRows = const [],
    this.draftIntakeMode = false,
  });

  final DatabaseService database;
  final Future<void> Function({required bool asDraft}) onSaved;
  final void Function(String sku, List<String?> slots)? onGallerySlotsSynced;
  final Map<String, dynamic>? editProduct;
  final List<Map<String, dynamic>> catalogRows;
  final bool draftIntakeMode;

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
  String _storeLocationCode = StoreLocationCode.unselected;
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

  List<String?> _gallerySlots =
      List<String?>.filled(kProductGallerySlotCount, null);
  final Map<int, XFile> _deferredBySlot = {};

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

  int get _totalPhotoCount =>
      countFilledGallerySlots(_gallerySlots) + _deferredBySlot.length;

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

    _storeLocationCode = storeLocationPickerCodeFromRow(edit);

    _skuController.text = edit['sku']?.toString().trim() ?? '';
    _weightController.text = _formatNumField(edit['weight_grams']);
    final editSize = productDisplaySizeFromRow(edit);
    _sizeController.text =
        editSize > 0 ? _formatNumField(editSize) : '';
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
    _gallerySlots = List<String?>.from(productGallerySlotsFromRow(edit));
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
    final productId = widget.editProduct?['id']?.toString().trim() ?? '';
    if (productId.isEmpty) return;
    try {
      final media =
          await widget.database.fetchProductMediaFieldsByProductId(productId);
      if (!mounted || media == null) return;
      final merged = Map<String, dynamic>.from(widget.editProduct!)
        ..['gallery_slots'] = media['gallery_slots']
        ..addAll(media);
      final slots = productGallerySlotsFromRow(merged);
      if (!slots.any((u) => (u?.trim().isNotEmpty ?? false))) return;
      setState(() => _gallerySlots = List<String?>.from(slots));
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
    if (index < 0 || index >= _gallerySlots.length) return;
    setState(() => _gallerySlots[index] = null);
  }

  Future<void> _confirmRemoveDeferredPhoto(int slotIndex) async {
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
    setState(() => _deferredBySlot.remove(slotIndex));
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

  String _resolvePhotoLookupSku() {
    final fromField = _skuController.text.trim();
    if (fromField.isNotEmpty) return fromField;
    if (_isEditMode) {
      return widget.editProduct?['sku']?.toString().trim() ?? '';
    }
    return '';
  }

  Future<void> _lookupPhotosBySku() async {
    if (_skuPhotoLookupInProgress || _saving) return;
    final sku = _resolvePhotoLookupSku();
    if (sku.isEmpty) {
      _showPhotoLookupNotice(
        message: 'Введите артикул для поиска фото',
        success: false,
      );
      return;
    }

    setState(() => _skuPhotoLookupInProgress = true);
    try {
      final lookup = await widget.database.findProductGalleryLookupBySku(
        sku,
        catalogRows: widget.catalogRows,
      );
      if (!mounted) return;
      if (lookup.images.isEmpty) {
        _showPhotoLookupNotice(
          message: 'Новых фото по артикулу не найдено',
          success: false,
        );
        return;
      }
      final merge = mergeDiscoveredGalleryIntoSlots(
        current: _gallerySlots,
        sourceSlots: lookup.sourceGallerySlots,
        extraUrls: lookup.images,
      );
      final added = merge.added;
      setState(() => _gallerySlots = merge.slots);
      if (added == 0) {
        _showPhotoLookupNotice(
          message: 'Новых фото по артикулу не найдено',
          success: false,
        );
        return;
      }
      _showPhotoLookupNotice(
        message: '✓ Подтянуто фото: $added',
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

  void _swapDialogGallerySlots(int a, int b) {
    if (_saving) return;
    setState(() {
      swapGallerySlotUrls(_gallerySlots, a, b);
      final da = _deferredBySlot.remove(a);
      final db = _deferredBySlot.remove(b);
      if (da != null) _deferredBySlot[b] = da;
      if (db != null) _deferredBySlot[a] = db;
    });
  }

  Future<void> _pickPhotoForSlot(int slotIndex) async {
    if (slotIndex < 0 || slotIndex >= kProductGallerySlotCount) return;
    if (_gallerySlots[slotIndex] != null &&
        _gallerySlots[slotIndex]!.trim().isNotEmpty) {
      return;
    }
    if (_deferredBySlot.containsKey(slotIndex)) return;

    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
    );
    if (picked == null || !mounted) return;

    setState(() => _deferredBySlot[slotIndex] = picked);
  }

  Future<void> _replacePhotoForSlot(int slotIndex) async {
    if (_saving) return;
    if (slotIndex < 0 || slotIndex >= kProductGallerySlotCount) return;

    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
    );
    if (picked == null || !mounted) return;

    setState(() {
      _gallerySlots[slotIndex] = null;
      _deferredBySlot[slotIndex] = picked;
    });
  }

  Future<bool> _finalizeProductGallery({
    required String sku,
    required String productId,
  }) async {
    var slots = List<String?>.from(_gallerySlots);
    if (_deferredBySlot.isNotEmpty) {
      slots = await _uploadDeferredPhotosBySlot(
        sku: sku,
        productId: productId,
      );
      if (mounted) {
        setState(() {
          _deferredBySlot.clear();
          _gallerySlots = slots;
        });
      }
    }
    final hasAny = slots.any((u) => (u?.trim().isNotEmpty ?? false));
    if (!hasAny) return true;

    final ok = await widget.database.updateProductGallerySlotsByProductId(
      productId: productId,
      gallerySlots: slots,
    );
    widget.onGallerySlotsSynced?.call(sku.trim(), slots);
    return ok;
  }

  Future<void> _pickPhotoToFirstEmptySlot() async {
    if (_totalPhotoCount >= ProductItem.maxGalleryImages) {
      _snack('Лимит ${ProductItem.maxGalleryImages} фото', error: true);
      return;
    }
    final slots = List<String?>.from(_gallerySlots);
    for (final e in _deferredBySlot.keys) {
      if (e >= 0 && e < slots.length) slots[e] = 'deferred';
    }
    final slot = firstEmptyGallerySlotIndex(slots);
    if (slot == null) return;
    await _pickPhotoForSlot(slot);
  }

  Future<List<String?>> _uploadDeferredPhotosBySlot({
    required String sku,
    required String productId,
  }) async {
    final slots = List<String?>.from(_gallerySlots);
    final entries = _deferredBySlot.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in entries) {
      final bytes = await entry.value.readAsBytes();
      final url = await widget.database.uploadProductGallerySlotImage(
        productId: productId,
        sku: sku,
        slotIndex: entry.key,
        bytes: bytes,
        contentType: entry.value.mimeType ?? 'image/jpeg',
      );
      if (url == null) {
        throw StateError('Не удалось загрузить ${entry.value.name}');
      }
      slots[entry.key] = url;
    }
    return slots;
  }

  /// После insert: локальные файлы → Storage; слоты по SKU через RPC.
  Future<void> _attachGalleryForNewManualProduct(String sku) async {
    final row = await widget.database.fetchProductRowForLabelBySku(sku);
    final productId = row?['id']?.toString().trim() ?? '';
    if (productId.isEmpty) return;

    final galleryOk = await _finalizeProductGallery(
      sku: sku,
      productId: productId,
    );
    if (!galleryOk && mounted) {
      _snack('Товар сохранён, но галерея фото не обновилась', error: true);
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
    if (!asDraft && _storeLocationCode == StoreLocationCode.unselected) {
      _snack(
        'Выберите магазин (Инчхон или Ансан) для размещения на витрине',
        error: true,
      );
      return;
    }
    await _submit(asDraft: asDraft);
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
    final priceRaw = int.tryParse(_priceController.text.replaceAll(RegExp(r'[^\d]'), ''));
    if (priceRaw == null || priceRaw <= 0) {
      _snack('Укажите цену продажи (₩) больше 0', error: true);
      return;
    }
    final price = roundKrwUpTo1000(priceRaw);

    setState(() => _saving = true);
    try {
      final size = double.tryParse(_sizeController.text.replaceAll(',', '.'));
      final notes = _notesController.text.trim();
      final manufacturer = _resolvedManufacturer;

      if (widget.draftIntakeMode && _isEditMode) {
        final productId = widget.editProduct!['id']?.toString().trim() ?? '';
        if (productId.isEmpty) {
          _snack('Нет id черновика', error: true);
          return;
        }
        final storeCode = _storeLocationCode == StoreLocationCode.unselected
            ? ''
            : normalizeStoreLocationCode(storeLocation: _storeLocationCode);
        final result = await widget.database.updateDraftProduct({
          'id': productId,
          'sku': sku,
          'name': productName,
          'category': productCategory,
          'metal_type': _resolvedMetalType,
          'metal': _resolvedMetalType,
          'insert': formatGemInsertsForStorage(
            catalog: _selectedCatalogGems,
            legacy: _legacyGemValues,
          ),
          'gem_inserts': formatGemInsertsForStorage(
            catalog: _selectedCatalogGems,
            legacy: _legacyGemValues,
          ),
          'weight_grams': weight,
          ...productSizeDbFieldsFromInput(size),
          'notes': notes,
          'manufacturer': manufacturer,
          'sale_price': price,
          'price': price,
          'store_location': storeCode,
        });
        if (!result.ok) {
          _snack(result.error ?? 'Не удалось обновить черновик', error: true);
          return;
        }
        final galleryOk = await _finalizeProductGallery(
          sku: sku,
          productId: productId,
        );
        if (!galleryOk) {
          _snack('Черновик сохранён, но галерея фото не обновилась', error: true);
        }
        await widget.onSaved(asDraft: true);
        if (!mounted) return;
        Navigator.pop(context, true);
        return;
      }

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
              writeStoreLocation: true,
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
        if (productId.isNotEmpty) {
          final galleryOk = await _finalizeProductGallery(
            sku: sku,
            productId: productId,
          );
          if (!galleryOk) {
            _snack(
              'Карточка сохранена, но галерея фото не обновилась',
              error: true,
            );
          }
        }
      } else {
        await _attachGalleryForNewManualProduct(sku);
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
        await printJewelryLabelPlatform(data);
      } catch (error, stackTrace) {
        debugPrint(
          'Тихая ошибка печати после ручного сохранения ($sku): $error',
        );
        debugPrint('$stackTrace');
      }
    });
  }

  bool _hasPhotoInSlot(int index) {
    if (index < 0 || index >= _gallerySlots.length) return false;
    final url = _gallerySlots[index];
    if (url != null && url.trim().isNotEmpty) return true;
    return _deferredBySlot.containsKey(index);
  }

  Widget _buildManualPhotoGrid() {
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 0.92,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: List.generate(kProductGallerySlotCount, (index) {
        final deferred = _deferredBySlot[index];
        final url = _gallerySlots[index];
        final filled = url != null && url.trim().isNotEmpty;
        return _ManualDialogPhotoSlot(
          slotLabel: kProductGallerySlotLabels[index],
          slotIndex: index,
          url: filled ? url : null,
          deferredFile: deferred,
          busy: _saving,
          onEmptyTap: _saving
              ? null
              : () => unawaited(_pickPhotoForSlot(index)),
          onReplaceTap: _hasPhotoInSlot(index)
              ? (_saving
                  ? null
                  : () => unawaited(_replacePhotoForSlot(index)))
              : null,
          onSwapLeft: index > 0 && !_saving
              ? () => _swapDialogGallerySlots(index - 1, index)
              : null,
          onSwapRight:
              index < kProductGallerySlotCount - 1 && !_saving
                  ? () => _swapDialogGallerySlots(index, index + 1)
                  : null,
          onRemove: filled
              ? () => _confirmRemoveNetworkPhoto(index)
              : (deferred != null
                  ? () => _confirmRemoveDeferredPhoto(index)
                  : null),
        );
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
              StoreLocationTriStateSelector(
                selectedCode: _storeLocationCode,
                onChanged: (code) {
                  setState(() => _storeLocationCode = code);
                  unawaited(_persistLastSelectedStoreLocation(code));
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
                onPressed: _saving ? null : _pickPhotoToFirstEmptySlot,
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
        widget.draftIntakeMode
            ? 'Редактирование черновика'
            : (_isEditMode ? 'Редактировать карточку' : 'Добавить товар'),
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
                  if (widget.draftIntakeMode) ...[
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _saving ? null : () => _requestSubmit(asDraft: true),
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Сохранить изменения'),
                    ),
                  ] else ...[
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
    this.slotLabel,
    this.slotIndex = 0,
    this.url,
    this.deferredFile,
    this.busy = false,
    this.onEmptyTap,
    this.onReplaceTap,
    this.onSwapLeft,
    this.onSwapRight,
    this.onRemove,
  });

  final String? slotLabel;
  final int slotIndex;
  final String? url;
  final XFile? deferredFile;
  final bool busy;
  final VoidCallback? onEmptyTap;
  final VoidCallback? onReplaceTap;
  final VoidCallback? onSwapLeft;
  final VoidCallback? onSwapRight;
  final VoidCallback? onRemove;

  bool get _hasPhoto =>
      (url != null && url!.isNotEmpty) || deferredFile != null;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
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
                      ? Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: onEmptyTap,
                            borderRadius: BorderRadius.circular(10),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add,
                                  color: AppColors.textSecondary
                                      .withValues(alpha: 0.75),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  slotLabel ?? 'Слот',
                                  style: AppTypography.productMeta(),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      : Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: busy ? null : onReplaceTap,
                            borderRadius: BorderRadius.circular(10),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: url != null && url!.isNotEmpty
                                  ? Image.network(
                                      url!,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => const Icon(
                                        Icons.broken_image_outlined,
                                      ),
                                    )
                                  : _DeferredPhotoPreview(file: deferredFile!),
                            ),
                          ),
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
        ),
        if (slotLabel != null) ...[
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (onSwapLeft != null)
                _GallerySlotArrowButton(
                  label: '◀',
                  busy: busy,
                  onTap: onSwapLeft!,
                ),
              Expanded(
                child: Text(
                  slotLabel!,
                  style: AppTypography.productMeta(),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (onSwapRight != null)
                _GallerySlotArrowButton(
                  label: '▶',
                  busy: busy,
                  onTap: onSwapRight!,
                ),
            ],
          ),
        ],
      ],
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

/// Редактирование черновика из экрана «Приёмка черновиков».
Future<bool> showManualProductDraftEditDialog(
  BuildContext context, {
  required DatabaseService database,
  required Map<String, dynamic> editProduct,
}) async {
  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => _ManualProductDialog(
      database: database,
      editProduct: editProduct,
      draftIntakeMode: true,
      onSaved: ({required bool asDraft}) async {},
    ),
  );
  return saved == true;
}
