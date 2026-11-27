import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/services/database_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/product_size_utils.dart';
import '../../../../core/utils/store_location_utils.dart';
import '../../../../core/utils/won_format.dart';
import '../../../../core/widgets/krw_text.dart';
import '../../../printing/domain/jewelry_label_data.dart';
import '../../../printing/presentation/widgets/jewelry_label_preview.dart';
import '../../../printing/infrastructure/browser_label_print.dart';
import '../../../printing/presentation/widgets/jewelry_label_print_dialog.dart';
import '../pages/jewelry_admin_dashboard.dart';
import '../widgets/admin_product_photo_preview.dart';
import '../../domain/draft_activate_result.dart';
import '../../domain/draft_batch_reconcile.dart';

enum _AdminDraftFilter { all, onShelf, sentAnsan }

/// Складская приёмка черновиков (`stock_quantity = 0` → `1`) + печать этикеток.
class DraftIntakeScreen extends StatefulWidget {
  DraftIntakeScreen({
    super.key,
    DatabaseService? database,
    this.sellerStaffMode = false,
    this.actorCode = 'ADMIN',
    this.onTransfersMutated,
  }) : database = database ?? DatabaseService.create();

  final DatabaseService database;
  final bool sellerStaffMode;
  final String actorCode;
  final VoidCallback? onTransfersMutated;

  @override
  State<DraftIntakeScreen> createState() => _DraftIntakeScreenState();
}

class _DraftIntakeScreenState extends State<DraftIntakeScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;

  List<Map<String, dynamic>> _drafts = const [];
  bool _searchLoading = false;
  bool _bulkBusy = false;
  bool _batchSendBusy = false;
  _AdminDraftFilter _adminDraftFilter = _AdminDraftFilter.onShelf;
  final Set<String> _rowBusyIds = {};
  final Set<String> _selectedDraftIds = {};

  List<Map<String, dynamic>> get _visibleDrafts {
    if (widget.sellerStaffMode) {
      return _drafts.where((row) {
        return row['store_location']?.toString() == 'ANS' &&
            row['status']?.toString() == 'in_transfer';
      }).toList();
    }
    return _drafts.where((row) {
      final status = row['status']?.toString();
      return switch (_adminDraftFilter) {
        _AdminDraftFilter.all => true,
        _AdminDraftFilter.onShelf =>
          status == 'hidden' || status == 'active',
        _AdminDraftFilter.sentAnsan => status == 'in_transfer',
      };
    }).toList();
  }

  /// Трансфер ICN→ANS: непринятый черновик (бейдж магазина не важен).
  static bool _canSendDraftToAnsan(Map<String, dynamic> row) {
    final status = row['status']?.toString();
    final stock = (row['stock_quantity'] as num?)?.toInt() ?? 0;
    return stock == 0 && (status == 'hidden' || status == 'active');
  }

  static bool _isDraftInTransitToAnsan(Map<String, dynamic> row) {
    return row['status']?.toString() == 'in_transfer';
  }

  static bool _canActivateDraft(Map<String, dynamic> row) {
    final stock = (row['stock_quantity'] as num?)?.toInt() ?? 0;
    if (stock != 0) return false;
    final status = row['status']?.toString();
    if (status != 'hidden' && status != 'active') {
      return false;
    }
    if (isStoreLocationUnsetInDatabase(row)) return false;
    final loc = normalizeStoreLocationCode(
      storeLocation: row['store_location']?.toString(),
      productRow: row,
    );
    return loc == StoreLocationCode.icn || loc == StoreLocationCode.ans;
  }

  List<Map<String, dynamic>> get _selectedVisibleRows => _visibleDrafts
      .where((row) {
        final id = _productId(row);
        return id != null && _selectedDraftIds.contains(id);
      })
      .toList();

  int get _selectedAnsanSendCount =>
      _selectedVisibleRows.where(_canSendDraftToAnsan).length;

  int get _selectedAcceptCount =>
      _selectedVisibleRows.where(_canActivateDraft).length;

  Iterable<String> get _visibleSelectableIds => _visibleDrafts
      .map(_productId)
      .whereType<String>();

  bool? get _masterCheckboxValue {
    final ids = _visibleSelectableIds.toList();
    if (ids.isEmpty) return false;
    final selected = ids.where(_selectedDraftIds.contains).length;
    if (selected == 0) return false;
    if (selected == ids.length) return true;
    return null;
  }

  void _clearDraftSelection() {
    if (_selectedDraftIds.isEmpty) return;
    setState(() => _selectedDraftIds.clear());
  }

  void _onMasterCheckboxChanged(bool? value) {
    final visibleIds = _visibleSelectableIds.toSet();
    setState(() {
      if (value == true) {
        _selectedDraftIds.addAll(visibleIds);
      } else {
        _selectedDraftIds.removeAll(visibleIds);
      }
    });
  }

  void _onRowSelectionChanged(String id, bool selected) {
    setState(() {
      if (selected) {
        _selectedDraftIds.add(id);
      } else {
        _selectedDraftIds.remove(id);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _runSearch(_searchController.text);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _runSearch(_searchController.text);
    });
  }

  Future<void> _runSearch(String query) async {
    setState(() => _searchLoading = true);
    try {
      final rows = await widget.database.searchDraftProducts(query);
      if (!mounted) return;
      setState(() {
        _drafts = rows;
        _selectedDraftIds.clear();
      });
    } catch (error) {
      if (!mounted) return;
      _showSnack('Ошибка поиска: $error', isError: true);
    } finally {
      if (mounted) setState(() => _searchLoading = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.saleRed : AppColors.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static String _field(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value == null) return '—';
    final text = value.toString().trim();
    return text.isEmpty ? '—' : text;
  }

  static double _weight(Map<String, dynamic> row) {
    return (row['weight_grams'] as num?)?.toDouble() ?? 0;
  }

  static double _size(Map<String, dynamic> row) =>
      productDisplaySizeFromRow(row);

  /// Как витрина админки: `sale_price`, затем legacy `price` (KRW).
  static int? _salePriceKrw(Map<String, dynamic> row) {
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

  static Widget _priceCell(Map<String, dynamic> row) {
    final krw = _salePriceKrw(row);
    if (krw == null) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Text(
          '—',
          maxLines: 1,
          style: AppTypography.productMeta().copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      );
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Text(
        formatWon(krw),
        maxLines: 1,
        style: AppTypography.price(fontSize: 13),
      ),
    );
  }

  static String? _thumbnailUrl(Map<String, dynamic> row) {
    final urls = adminProductImageUrls(row);
    return urls.isEmpty ? null : urls.first;
  }

  Future<void> _openDraftPhotoPreview(Map<String, dynamic> row) async {
    final urls = adminProductImageUrls(row);
    if (urls.isEmpty) return;
    final sku = _field(row, 'sku');
    await showAdminProductPhotoPreview(
      context,
      title: sku,
      imageUrls: urls,
    );
  }

  Future<String?> _confirmAcceptWithPreview(Map<String, dynamic> row) async {
    final sku = _field(row, 'sku');
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => _DraftAcceptPreviewDialog(row: row, sku: sku),
    );
  }

  Future<String?> _promptStoreLocationForAccept() {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Укажите магазин для приёмки этого товара',
          style: AppTypography.heading(fontSize: 17),
        ),
        contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx, StoreLocationCode.icn),
            style: FilledButton.styleFrom(
              backgroundColor: storeLocationBadgeColors(StoreLocationCode.icn).fg,
              foregroundColor: Colors.white,
            ),
            child: const Text('Инчхон'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, StoreLocationCode.ans),
            style: FilledButton.styleFrom(
              backgroundColor: storeLocationBadgeColors(StoreLocationCode.ans).fg,
              foregroundColor: Colors.white,
            ),
            child: const Text('Ансан'),
          ),
        ],
      ),
    );
  }

  Future<bool> _ensureDraftStoreBeforeAccept(Map<String, dynamic> row) async {
    if (!isStoreLocationUnsetInDatabase(row)) return true;

    final picked = await _promptStoreLocationForAccept();
    if (picked == null || !mounted) return false;

    final productId = row['id']?.toString().trim() ?? '';
    if (productId.isEmpty) {
      _showSnack('Нет id черновика', isError: true);
      return false;
    }

    final res = await widget.database.setDraftProductStoreLocation(
      id: productId,
      storeLocation: picked,
    );
    if (!mounted) return false;
    if (!res.ok) {
      _showSnack(res.error ?? 'Не удалось сохранить магазин', isError: true);
      return false;
    }
    row['store_location'] = picked;
    return true;
  }

  Future<void> _cycleDraftStoreLocation(Map<String, dynamic> row) async {
    final productId = row['id']?.toString().trim() ?? '';
    final sku = _field(row, 'sku');
    if (productId.isEmpty) {
      _showSnack('Нет id черновика', isError: true);
      return;
    }

    final currentRaw = isStoreLocationUnsetInDatabase(row)
        ? null
        : row['store_location']?.toString();
    final nextDb = cycleDraftStoreLocationPicker(currentRaw);
    final previousSnapshot = Map<String, dynamic>.from(row);

    setState(() {
      _drafts = _drafts.map((draft) {
        final id = draft['id']?.toString().trim();
        if (id == productId) {
          return Map<String, dynamic>.from(draft)
            ..['store_location'] = nextDb;
        }
        return draft;
      }).toList(growable: false);
    });

    final res = await widget.database.setDraftProductStoreLocation(
      id: productId,
      storeLocation: nextDb,
    );
    if (!mounted) return;
    if (res.ok) return;

    setState(() {
      _drafts = _drafts.map((draft) {
        final id = draft['id']?.toString().trim();
        if (id == productId) return previousSnapshot;
        return draft;
      }).toList(growable: false);
    });
    _showSnack(
      '${res.error ?? 'Ошибка сохранения магазина'} ($sku)',
      isError: true,
    );
  }

  void _safeFireAndForgetPrint(Map<String, dynamic> productRow) {
    Future.microtask(() async {
      try {
        final data = JewelryLabelData.fromProductMap(productRow);
        await printJewelryLabelsPlatform([data]);
      } catch (error, stackTrace) {
        debugPrint('Тихая ошибка печати бирки 12×60: $error');
        debugPrint('$stackTrace');
      }
    });
  }

  Future<void> _printLabelForProduct(
    Map<String, dynamic> row, {
    bool userFeedback = true,
  }) async {
    try {
      await JewelryLabelPrintDialog.showAndPrint(
        context,
        productRow: row,
        titleSuffix: 'Приёмка',
      );
      if (userFeedback && mounted) {
        _showSnack('Печать ценника запущена');
      }
    } catch (error, stackTrace) {
      debugPrint('DraftIntakeScreen._printLabelForProduct failed: $error');
      debugPrint('$stackTrace');
      if (userFeedback && mounted) {
        _showSnack('Ошибка печати: $error', isError: true);
      }
      rethrow;
    }
  }

  static String? _productId(Map<String, dynamic> row) {
    final id = row['id']?.toString().trim();
    if (id == null || id.isEmpty) return null;
    return id;
  }

  void _showTransferAutoCloseSnackIfNeeded(DraftActivateResult result) {
    final resolution = result.transferResolution?.trim().toLowerCase();
    if (resolution == null || resolution.isEmpty) return;

    final from = result.transferFrom ?? '—';
    final to = result.transferTo ?? '—';
    final message = switch (resolution) {
      'cancelled' =>
        'Висящий трансфер $from→$to отменён (приёмка не совпала с маршрутом).',
      'completed' =>
        'Трансфер $from→$to закрыт — совпал с магазином приёмки.',
      _ => null,
    };
    if (message != null) {
      _showSnack(message);
    }
  }

  static String? _storeCodeForActivate(Map<String, dynamic> row) {
    if (isStoreLocationUnsetInDatabase(row)) return null;
    return normalizeStoreLocationCode(
      storeLocation: row['store_location']?.toString(),
      productRow: row,
    );
  }

  Future<void> _acceptSingle(Map<String, dynamic> row) async {
    final sku = _field(row, 'sku');
    final productId = _productId(row);
    if (sku == '—' || productId == null) {
      _showSnack('Нет id черновика', isError: true);
      return;
    }

    final productName = await _confirmAcceptWithPreview(row);
    if (productName == null || !mounted) return;

    final storeReady = await _ensureDraftStoreBeforeAccept(row);
    if (!storeReady || !mounted) return;

    final storeCode = _storeCodeForActivate(row);

    setState(() => _rowBusyIds.add(productId));
    try {
      final result = await widget.database.activateDraftProductById(
        id: productId,
        notes: productName,
        storeLocation: storeCode,
      );
      if (!mounted) return;
      if (!result.ok) {
        _showSnack(
          result.error ?? 'Не удалось активировать (уже принят?)',
          isError: true,
        );
        return;
      }

      widget.onTransfersMutated?.call();
      _showTransferAutoCloseSnackIfNeeded(result);

      final printRow = Map<String, dynamic>.from(row)..['notes'] = productName;
      _showSnack('Принят 1 экз. $sku — на витрине (stock=1)');
      _safeFireAndForgetPrint(printRow);
      await _runSearch(_searchController.text);
    } catch (error) {
      if (!mounted) return;
      _showSnack('Ошибка приёмки: $error', isError: true);
    } finally {
      if (mounted) setState(() => _rowBusyIds.remove(productId));
    }
  }

  Future<void> _editSingle(Map<String, dynamic> row) async {
    final sku = _field(row, 'sku');
    final productId = _productId(row);
    if (sku == '—' || productId == null) return;

    setState(() => _rowBusyIds.add(productId));
    try {
      final editRow = Map<String, dynamic>.from(row);
      final media = await widget.database.fetchProductMediaFieldsBySku(sku);
      if (media != null) {
        editRow.addAll(media);
      }
      if (!mounted) return;
      final saved = await showManualProductDraftEditDialog(
        context,
        database: widget.database,
        editProduct: editRow,
      );
      if (!mounted || !saved) return;
      _showSnack('Черновик $sku обновлён');
      await _runSearch(_searchController.text);
    } catch (error) {
      if (!mounted) return;
      _showSnack('Ошибка редактирования: $error', isError: true);
    } finally {
      if (mounted) setState(() => _rowBusyIds.remove(productId));
    }
  }

  Future<void> _deleteSingle(Map<String, dynamic> row) async {
    final sku = _field(row, 'sku');
    if (sku == '—') return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Удалить черновик?', style: AppTypography.heading(fontSize: 18)),
        content: Text(
          'SKU $sku будет удалён из базы без возможности восстановления.',
          style: AppTypography.productMeta(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.saleRed),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final productId = _productId(row);
    if (productId == null) {
      _showSnack('Нет id черновика', isError: true);
      return;
    }
    setState(() => _rowBusyIds.add(productId));
    try {
      final res = await widget.database.deleteDraftProduct(
        id: productId,
        sku: sku,
      );
      if (!mounted) return;
      if (!res.ok) {
        _showSnack(
          'Не удалось удалить $sku: ${res.error ?? 'неизвестная ошибка'}',
          isError: true,
        );
        return;
      }
      setState(() {
        _drafts = _drafts
            .where((draft) => _productId(draft) != productId)
            .toList(growable: false);
        _selectedDraftIds.remove(productId);
      });
      _showSnack('Черновик $sku удалён');
      await _runSearch(_searchController.text);
    } catch (error) {
      if (!mounted) return;
      _showSnack('Ошибка удаления: $error', isError: true);
    } finally {
      if (mounted) setState(() => _rowBusyIds.remove(productId));
    }
  }

  Future<void> _showBatchReconcile() async {
    final query = _searchController.text.trim();
    final scopeSubtitle = query.isEmpty
        ? 'По всем черновикам в текущем списке (поиск не задан)'
        : 'По результатам поиска: «$query»';

    final report = computeDraftBatchReconcileReport(
      _drafts,
      weightGramsForRow: _weight,
      priceKrwForRow: (row) => _salePriceKrw(row) ?? 0,
    );

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _DraftBatchReconcileDialog(
        report: report,
        scopeSubtitle: scopeSubtitle,
        totalRows: _drafts.length,
      ),
    );
  }

  Future<void> _sendBatchToAnsan() async {
    final selected = _selectedVisibleRows;
    if (selected.isEmpty) {
      _showSnack('Отметьте черновики для отправки', isError: true);
      return;
    }
    final sendable =
        selected.where(_canSendDraftToAnsan).toList(growable: false);
    final skipped = selected.length - sendable.length;
    if (sendable.isEmpty) {
      _showSnack(
        'Среди выбранных нет непринятых черновиков (stock=0, hidden/active). '
        'Уже «в пути» или принятые позиции пропускаются.',
        isError: true,
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отправить в Ансан?'),
        content: Text(
          skipped > 0
              ? 'Создать трансферы ICN→ANS для ${sendable.length} черновиков и '
                  'распечатать бирки 12×60 мм? '
                  '(ещё $skipped уже в пути или не подходят.)'
              : 'Создать трансферы ICN→ANS для ${sendable.length} черновиков и '
                  'распечатать бирки 12×60 мм?',
          style: AppTypography.productMeta(),
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
    );
    if (confirmed != true || !mounted) return;
    setState(() => _batchSendBusy = true);
    try {
      final ids = sendable
          .map(_productId)
          .whereType<String>()
          .toList(growable: false);
      final result = await widget.database.sendDraftsToAnsanByIds(
        actorCode: widget.actorCode,
        productIds: ids,
      );
      if (result['ok'] != true) {
        _showSnack(
          result['error']?.toString() ?? 'Партия не отправлена',
          isError: true,
        );
        return;
      }
      final count = (result['sent_count'] as num?)?.toInt() ?? sendable.length;
      for (final row in sendable) {
        _safeFireAndForgetPrint(row);
      }
      _showSnack(
        'Трансферы ICN→ANS: $count поз. — бирки отправлены на печать',
      );
      widget.onTransfersMutated?.call();
      _clearDraftSelection();
      await _runSearch(_searchController.text);
    } catch (error) {
      _showSnack('Ошибка: $error', isError: true);
    } finally {
      if (mounted) setState(() => _batchSendBusy = false);
    }
  }

  Future<void> _acceptSelectedDrafts() async {
    final selected = _selectedVisibleRows;
    if (selected.isEmpty) {
      _showSnack('Отметьте черновики для приёмки', isError: true);
      return;
    }
    final activatable =
        selected.where(_canActivateDraft).toList(growable: false);
    final skipped = selected.length - activatable.length;
    if (activatable.isEmpty) {
      _showSnack(
        'Среди выбранных нет позиций для приёмки (нужен магазин ICN/ANS)',
        isError: true,
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Принять выбранное?',
          style: AppTypography.heading(fontSize: 18),
        ),
        content: Text(
          skipped > 0
              ? 'Будет активировано: ${activatable.length} поз. '
                  '(ещё $skipped в выборе будут пропущены). '
                  'Этикетки уйдут в буфер печати.'
              : 'Будет активировано: ${activatable.length} поз. '
                  'и отправлено в общий буфер печати этикеток.',
          style: AppTypography.productMeta(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Принять'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _bulkBusy = true);
    try {
      final ids = activatable
          .map(_productId)
          .whereType<String>()
          .toList(growable: false);
      final activated = await widget.database.activateDraftProductsByIds(ids);
      if (!mounted) return;

      if (activated <= 0) {
        _showSnack('Не удалось активировать выбранные черновики', isError: true);
        return;
      }

      widget.onTransfersMutated?.call();

      for (final row in activatable) {
        _safeFireAndForgetPrint(row);
      }

      _showSnack('Активировано $activated поз. — буфер печати сформирован');
      _clearDraftSelection();
      await _runSearch(_searchController.text);
    } catch (error) {
      if (!mounted) return;
      _showSnack('Ошибка массовой приёмки: $error', isError: true);
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final kpiReport = computeDraftBatchReconcileReport(
      _visibleDrafts,
      weightGramsForRow: _weight,
      priceKrwForRow: (row) => _salePriceKrw(row) ?? 0,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          widget.sellerStaffMode
              ? 'Приёмка поставки (Ансан)'
              : 'Приёмка черновиков',
          style: AppTypography.heading(fontSize: 20),
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width >= 1200 ? 1200 : width),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Toolbar(
                  sellerStaffMode: widget.sellerStaffMode,
                  searchController: _searchController,
                  searchLoading: _searchLoading,
                  bulkBusy: _bulkBusy,
                  batchSendBusy: _batchSendBusy,
                  selectedAnsanSendCount: _selectedAnsanSendCount,
                  selectedAcceptCount: _selectedAcceptCount,
                  adminDraftFilter: _adminDraftFilter,
                  onSubmitted: (value) => _runSearch(value),
                  onBulkAccept: _acceptSelectedDrafts,
                  onBatchReconcile: _showBatchReconcile,
                  onSendBatchToAnsan: _sendBatchToAnsan,
                  onAdminFilterChanged: (filter) => setState(() {
                    _adminDraftFilter = filter;
                    _selectedDraftIds.clear();
                  }),
                  kpiReport: kpiReport,
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _DraftTable(
                    drafts: _visibleDrafts,
                    loading: _searchLoading,
                    busyIds: _rowBusyIds,
                    showAdminActions: !widget.sellerStaffMode,
                    selectionEnabled: !widget.sellerStaffMode,
                    selectedIds: _selectedDraftIds,
                    masterCheckboxValue: _masterCheckboxValue,
                    onMasterCheckboxChanged: _onMasterCheckboxChanged,
                    onRowSelectionChanged: _onRowSelectionChanged,
                    onAcceptRow: _acceptSingle,
                    onPrintRow: _printLabelForProduct,
                    onEditRow: _editSingle,
                    onDeleteRow: _deleteSingle,
                    onCycleStoreLocation: _cycleDraftStoreLocation,
                    onOpenGallery: _openDraftPhotoPreview,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.sellerStaffMode,
    required this.searchController,
    required this.searchLoading,
    required this.bulkBusy,
    required this.batchSendBusy,
    required this.selectedAnsanSendCount,
    required this.selectedAcceptCount,
    required this.adminDraftFilter,
    required this.onSubmitted,
    required this.onBulkAccept,
    required this.onBatchReconcile,
    required this.onSendBatchToAnsan,
    required this.onAdminFilterChanged,
    required this.kpiReport,
  });

  final bool sellerStaffMode;
  final TextEditingController searchController;
  final bool searchLoading;
  final bool bulkBusy;
  final bool batchSendBusy;
  final int selectedAnsanSendCount;
  final int selectedAcceptCount;
  final _AdminDraftFilter adminDraftFilter;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onBulkAccept;
  final VoidCallback onBatchReconcile;
  final VoidCallback onSendBatchToAnsan;
  final ValueChanged<_AdminDraftFilter> onAdminFilterChanged;
  final DraftBatchReconcileReport kpiReport;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!sellerStaffMode) ...[
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  Text('Статус:', style: AppTypography.caption()),
                  for (final (value, label) in [
                    (_AdminDraftFilter.all, 'Все'),
                    (_AdminDraftFilter.onShelf, 'Новые / На складе'),
                    (_AdminDraftFilter.sentAnsan, 'Отправлены в Ансан'),
                  ])
                    ChoiceChip(
                      label: Text(label),
                      selected: adminDraftFilter == value,
                      onSelected: (_) => onAdminFilterChanged(value),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: batchSendBusy || selectedAnsanSendCount == 0
                          ? null
                          : onSendBatchToAnsan,
                      icon: batchSendBusy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.flight_takeoff_outlined),
                      label: Text(
                        'Отправить партию в Ансан ($selectedAnsanSendCount)',
                      ),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.textOnPrimary,
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            if (!sellerStaffMode)
              Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed:
                        bulkBusy || selectedAcceptCount == 0 ? null : onBulkAccept,
                    icon: bulkBusy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.inventory_2_outlined),
                    label: Text(
                      'Принять выбранное ($selectedAcceptCount)',
                      textAlign: TextAlign.center,
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: AppColors.textOnAccent,
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 12,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onBatchReconcile,
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('Сверка партии'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textPrimary,
                      side: const BorderSide(color: AppColors.accent, width: 1.5),
                      backgroundColor: AppColors.accent.withValues(alpha: 0.08),
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (sellerStaffMode) const SizedBox(height: 0) else const SizedBox(height: 16),
            TextField(
              controller: searchController,
              onSubmitted: onSubmitted,
              decoration: InputDecoration(
                labelText: 'Артикул, вес (г) или «Au585 2.43»',
                hintText: 'Быстрый поиск среди черновиков',
                prefixIcon: searchLoading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Icon(Icons.search),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _DraftIntakeKpiStrip(report: kpiReport),
          ],
        ),
      ),
    );
  }
}

class _DraftIntakeKpiStrip extends StatelessWidget {
  const _DraftIntakeKpiStrip({required this.report});

  final DraftBatchReconcileReport report;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 700;
    final grand = report.grandTotal;
    const silverAccent = Color(0xFF6B7280);
    final metaStyle = AppTypography.productMeta().copyWith(
      fontSize: 12,
      color: AppColors.textSecondary,
    );
    final valueStyle = AppTypography.productMeta().copyWith(
      fontWeight: FontWeight.w600,
      fontSize: 12,
    );

    Widget block(
      String title,
      DraftBatchGroupTotals stats,
      Color accent,
    ) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: AppTypography.caption().copyWith(
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
            const SizedBox(height: 4),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              runSpacing: 2,
              children: [
                Text('${stats.count} шт.', style: valueStyle),
                Text('·', style: metaStyle),
                Text(
                  '${stats.weightGrams.toStringAsFixed(2)} г',
                  style: valueStyle,
                ),
                Text('·', style: metaStyle),
                KrwText(
                  amount: stats.priceKrw,
                  currencyColor: AppColors.currencyWonAccent,
                  style: valueStyle,
                  digitStyle: valueStyle,
                ),
              ],
            ),
          ],
        ),
      );
    }

    final blocks = [
      block('Золото', report.gold, AppColors.bannerGoldEnd),
      block('Серебро', report.silver, silverAccent),
      block('Итого', grand, AppColors.accent),
    ];

    if (compact) {
      final itemWidth = width < 420 ? double.infinity : (width - 72) / 2;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final child in blocks)
            SizedBox(
              width: itemWidth,
              child: child,
            ),
        ],
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: blocks[0]),
          const SizedBox(width: 8),
          Expanded(child: blocks[1]),
          const SizedBox(width: 8),
          Expanded(child: blocks[2]),
        ],
      ),
    );
  }
}

abstract final class _DraftTableLayout {
  static const narrowBreakpoint = 680.0;
  static const photoSize = 40.0;
  static const checkboxColumnWidth = 36.0;
  static const actionsWidth = 164.0;
  static const horizontalPadding = 12.0;
  static const rowVerticalPadding = 10.0;
}

class _DraftTable extends StatelessWidget {
  const _DraftTable({
    required this.drafts,
    required this.loading,
    required this.busyIds,
    required this.onAcceptRow,
    required this.onPrintRow,
    required this.onEditRow,
    required this.onDeleteRow,
    required this.onCycleStoreLocation,
    required this.onOpenGallery,
    this.showAdminActions = true,
    this.selectionEnabled = false,
    this.selectedIds = const {},
    this.masterCheckboxValue,
    this.onMasterCheckboxChanged,
    this.onRowSelectionChanged,
  });

  final List<Map<String, dynamic>> drafts;
  final bool loading;
  final Set<String> busyIds;
  final bool showAdminActions;
  final bool selectionEnabled;
  final Set<String> selectedIds;
  final bool? masterCheckboxValue;
  final ValueChanged<bool?>? onMasterCheckboxChanged;
  final void Function(String id, bool selected)? onRowSelectionChanged;
  final Future<void> Function(Map<String, dynamic> row) onAcceptRow;
  final Future<void> Function(Map<String, dynamic> row) onPrintRow;
  final Future<void> Function(Map<String, dynamic> row) onEditRow;
  final Future<void> Function(Map<String, dynamic> row) onDeleteRow;
  final Future<void> Function(Map<String, dynamic> row) onCycleStoreLocation;
  final Future<void> Function(Map<String, dynamic> row) onOpenGallery;

  @override
  Widget build(BuildContext context) {
    if (loading && drafts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (drafts.isEmpty) {
      return Center(
        child: Text(
          'Черновики не найдены',
          style: AppTypography.productMeta().copyWith(fontSize: 16),
        ),
      );
    }

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < _DraftTableLayout.narrowBreakpoint;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DraftTableHeader(
                narrow: narrow,
                selectionEnabled: selectionEnabled,
                masterCheckboxValue: masterCheckboxValue,
                onMasterCheckboxChanged: onMasterCheckboxChanged,
              ),
              const Divider(height: 1, color: AppColors.border),
              Expanded(
                child: ListView.separated(
                  itemCount: drafts.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: AppColors.border),
                  itemBuilder: (context, index) {
                    final row = drafts[index];
                    final sku = _DraftIntakeScreenState._field(row, 'sku');
                    final rowId =
                        _DraftIntakeScreenState._productId(row) ?? '';
                    final busy = busyIds.contains(rowId);
                    final selected =
                        rowId.isNotEmpty && selectedIds.contains(rowId);
                    return narrow
                        ? _DraftTableNarrowRow(
                            row: row,
                            sku: sku,
                            busy: busy,
                            rowId: rowId,
                            selectionEnabled: selectionEnabled,
                            selected: selected,
                            onSelectionChanged: rowId.isEmpty
                                ? null
                                : (value) => onRowSelectionChanged
                                    ?.call(rowId, value),
                            onAccept: () => onAcceptRow(row),
                            onPrint: () => onPrintRow(row),
                            onEdit: () => onEditRow(row),
                            onDelete: () => onDeleteRow(row),
                            onCycleStore: () => onCycleStoreLocation(row),
                            onOpenGallery: () => onOpenGallery(row),
                            showAdminActions: showAdminActions,
                          )
                        : _DraftTableWideRow(
                            row: row,
                            sku: sku,
                            busy: busy,
                            rowId: rowId,
                            selectionEnabled: selectionEnabled,
                            selected: selected,
                            onSelectionChanged: rowId.isEmpty
                                ? null
                                : (value) => onRowSelectionChanged
                                    ?.call(rowId, value),
                            onAccept: () => onAcceptRow(row),
                            onPrint: () => onPrintRow(row),
                            onEdit: () => onEditRow(row),
                            onDelete: () => onDeleteRow(row),
                            onCycleStore: () => onCycleStoreLocation(row),
                            onOpenGallery: () => onOpenGallery(row),
                            showAdminActions: showAdminActions,
                          );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DraftTableHeader extends StatelessWidget {
  const _DraftTableHeader({
    required this.narrow,
    this.selectionEnabled = false,
    this.masterCheckboxValue,
    this.onMasterCheckboxChanged,
  });

  final bool narrow;
  final bool selectionEnabled;
  final bool? masterCheckboxValue;
  final ValueChanged<bool?>? onMasterCheckboxChanged;

  static TextStyle get _labelStyle =>
      AppTypography.caption(fontWeight: FontWeight.w700);

  @override
  Widget build(BuildContext context) {
    final pad = const EdgeInsets.symmetric(
      horizontal: _DraftTableLayout.horizontalPadding,
      vertical: _DraftTableLayout.rowVerticalPadding,
    );
    if (narrow) {
      return Container(
        color: AppColors.cardBackground,
        padding: pad,
        child: Row(
          children: [
            if (selectionEnabled) ...[
              SizedBox(
                width: _DraftTableLayout.checkboxColumnWidth,
                child: Checkbox(
                  tristate: true,
                  value: masterCheckboxValue,
                  onChanged: onMasterCheckboxChanged,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Expanded(child: Text('Черновики', style: _labelStyle)),
          ],
        ),
      );
    }
    return Container(
      color: AppColors.cardBackground,
      padding: pad,
      child: Row(
        children: [
          if (selectionEnabled)
            SizedBox(
              width: _DraftTableLayout.checkboxColumnWidth,
              child: Checkbox(
                tristate: true,
                value: masterCheckboxValue,
                onChanged: onMasterCheckboxChanged,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          if (selectionEnabled) const SizedBox(width: 4),
          const SizedBox(width: _DraftTableLayout.photoSize),
          const SizedBox(width: 8),
          const Expanded(flex: 3, child: _DraftHeaderCell('SKU')),
          const Expanded(flex: 2, child: _DraftHeaderCell('Магазин')),
          const Expanded(flex: 2, child: _DraftHeaderCell('Металл')),
          const Expanded(flex: 1, child: _DraftHeaderCell('Вес, г')),
          const Expanded(flex: 1, child: _DraftHeaderCell('Размер')),
          const Expanded(flex: 2, child: _DraftHeaderCell('Вставки')),
          const Expanded(flex: 2, child: _DraftHeaderCell('Цена', alignEnd: true)),
          SizedBox(
            width: _DraftTableLayout.actionsWidth,
            child: Text('Действие', style: _labelStyle, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

class _DraftHeaderCell extends StatelessWidget {
  const _DraftHeaderCell(this.label, {this.alignEnd = false});

  final String label;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: alignEnd ? TextAlign.end : TextAlign.start,
      style: _DraftTableHeader._labelStyle,
    );
  }
}

class _DraftTableWideRow extends StatelessWidget {
  const _DraftTableWideRow({
    required this.row,
    required this.sku,
    required this.busy,
    required this.rowId,
    this.selectionEnabled = false,
    this.selected = false,
    this.onSelectionChanged,
    required this.onAccept,
    required this.onPrint,
    required this.onEdit,
    required this.onDelete,
    required this.onCycleStore,
    required this.onOpenGallery,
    this.showAdminActions = true,
  });

  final Map<String, dynamic> row;
  final String sku;
  final bool busy;
  final String rowId;
  final bool selectionEnabled;
  final bool selected;
  final ValueChanged<bool>? onSelectionChanged;
  final VoidCallback onAccept;
  final VoidCallback onPrint;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onCycleStore;
  final VoidCallback onOpenGallery;
  final bool showAdminActions;

  @override
  Widget build(BuildContext context) {
    final thumbUrl = _DraftIntakeScreenState._thumbnailUrl(row);
    final canPreview =
        thumbUrl != null && thumbUrl.isNotEmpty && adminProductImageUrls(row).isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _DraftTableLayout.horizontalPadding,
        vertical: _DraftTableLayout.rowVerticalPadding,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (selectionEnabled) ...[
            SizedBox(
              width: _DraftTableLayout.checkboxColumnWidth,
              child: Checkbox(
                value: selected,
                onChanged: busy || onSelectionChanged == null
                    ? null
                    : (value) => onSelectionChanged!(value ?? false),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 4),
          ],
          _DraftThumbnail(
            url: thumbUrl,
            size: _DraftTableLayout.photoSize,
            onTap: canPreview ? onOpenGallery : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: _DraftEllipsisText(
              _DraftIntakeScreenState._field(row, 'sku'),
              style: AppTypography.caption(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerLeft,
              child: StoreLocationClickableBadge(
                code: storeLocationCodeFromProductRow(row),
                showCycleIcon: showAdminActions,
                onTap: !showAdminActions || busy ? null : onCycleStore,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: _DraftEllipsisText(
              _DraftIntakeScreenState._field(row, 'metal_type'),
            ),
          ),
          Expanded(
            flex: 1,
            child: _DraftFittedText(
              _DraftIntakeScreenState._weight(row).toStringAsFixed(2),
            ),
          ),
          Expanded(
            flex: 1,
            child: _DraftFittedText(
              _DraftIntakeScreenState._size(row).toStringAsFixed(2),
            ),
          ),
          Expanded(
            flex: 2,
            child: _DraftEllipsisText(
              _DraftIntakeScreenState._field(row, 'gem_inserts'),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: _DraftIntakeScreenState._priceCell(row),
            ),
          ),
          SizedBox(
            width: _DraftTableLayout.actionsWidth,
            child: _DraftRowActions(
              busy: busy,
              showInTransitBadge:
                  _DraftIntakeScreenState._isDraftInTransitToAnsan(row),
              onAccept: onAccept,
              onPrint: onPrint,
              onEdit: onEdit,
              onDelete: onDelete,
              showAdminActions: showAdminActions,
            ),
          ),
        ],
      ),
    );
  }
}

class _DraftTableNarrowRow extends StatelessWidget {
  const _DraftTableNarrowRow({
    required this.row,
    required this.sku,
    required this.busy,
    required this.rowId,
    this.selectionEnabled = false,
    this.selected = false,
    this.onSelectionChanged,
    required this.onAccept,
    required this.onPrint,
    required this.onEdit,
    required this.onDelete,
    required this.onCycleStore,
    required this.onOpenGallery,
    this.showAdminActions = true,
  });

  final Map<String, dynamic> row;
  final String sku;
  final bool busy;
  final String rowId;
  final bool selectionEnabled;
  final bool selected;
  final ValueChanged<bool>? onSelectionChanged;
  final VoidCallback onAccept;
  final VoidCallback onPrint;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onCycleStore;
  final VoidCallback onOpenGallery;
  final bool showAdminActions;

  @override
  Widget build(BuildContext context) {
    final metaStyle = AppTypography.productMeta();
    final weight = _DraftIntakeScreenState._weight(row).toStringAsFixed(2);
    final size = _DraftIntakeScreenState._size(row).toStringAsFixed(2);
    final metal = _DraftIntakeScreenState._field(row, 'metal_type');
    final inserts = _DraftIntakeScreenState._field(row, 'gem_inserts');
    final thumbUrl = _DraftIntakeScreenState._thumbnailUrl(row);
    final canPreview =
        thumbUrl != null && thumbUrl.isNotEmpty && adminProductImageUrls(row).isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _DraftTableLayout.horizontalPadding,
        vertical: _DraftTableLayout.rowVerticalPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (selectionEnabled)
                SizedBox(
                  width: _DraftTableLayout.checkboxColumnWidth,
                  child: Checkbox(
                    value: selected,
                    onChanged: busy || onSelectionChanged == null
                        ? null
                        : (value) => onSelectionChanged!(value ?? false),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              if (selectionEnabled) const SizedBox(width: 6),
              _DraftThumbnail(
                url: thumbUrl,
                size: _DraftTableLayout.photoSize,
                onTap: canPreview ? onOpenGallery : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: _DraftEllipsisText(
                        sku,
                        style: AppTypography.caption(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 4),
                    StoreLocationClickableBadge(
                      code: storeLocationCodeFromProductRow(row),
                      showCycleIcon: showAdminActions,
                      compact: true,
                      onTap: !showAdminActions || busy ? null : onCycleStore,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Flexible(child: _DraftIntakeScreenState._priceCell(row)),
              const SizedBox(width: 4),
              _DraftRowActions(
                busy: busy,
                showInTransitBadge:
                    _DraftIntakeScreenState._isDraftInTransitToAnsan(row),
                onAccept: onAccept,
                onPrint: onPrint,
                onEdit: onEdit,
                onDelete: onDelete,
                showAdminActions: showAdminActions,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _DraftEllipsisText(
                  '$metal · $weight г · р. $size · $inserts',
                  style: metaStyle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DraftEllipsisText extends StatelessWidget {
  const _DraftEllipsisText(this.text, {this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style ?? AppTypography.productMeta(),
    );
  }
}

class _DraftFittedText extends StatelessWidget {
  const _DraftFittedText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 1,
        style: AppTypography.productMeta(),
      ),
    );
  }
}

class _DraftRowActions extends StatelessWidget {
  const _DraftRowActions({
    required this.busy,
    required this.onAccept,
    required this.onPrint,
    required this.onEdit,
    required this.onDelete,
    this.showAdminActions = true,
    this.compact = false,
    this.showInTransitBadge = false,
  });

  final bool busy;
  final bool showInTransitBadge;
  final VoidCallback onAccept;
  final VoidCallback onPrint;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final bool showAdminActions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final acceptStyle = FilledButton.styleFrom(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: 4,
      ),
      minimumSize: Size(compact ? 0 : 0, 30),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
    final iconConstraints = BoxConstraints(
      minWidth: compact ? 28 : 32,
      minHeight: compact ? 28 : 32,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (showInTransitBadge)
          Tooltip(
            message: 'Трансфер ICN→ANS; приёмка — в Ансане по QR',
            child: Chip(
              label: Text(
                compact ? 'В пути' : 'В пути → ANS',
                style: AppTypography.productMeta().copyWith(
                  fontSize: compact ? 10 : 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              avatar: Icon(
                Icons.local_shipping_outlined,
                size: compact ? 14 : 16,
                color: AppColors.textSecondary,
              ),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 6),
              backgroundColor: AppColors.border.withValues(alpha: 0.35),
              side: const BorderSide(color: AppColors.border),
            ),
          )
        else
          FilledButton.tonal(
            onPressed: busy ? null : onAccept,
            style: acceptStyle,
            child: busy
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(compact ? 'Прин.' : 'Принять'),
          ),
        if (showAdminActions)
          IconButton(
            tooltip: 'Редактировать черновик',
            onPressed: busy ? null : onEdit,
            padding: EdgeInsets.zero,
            constraints: iconConstraints,
            iconSize: compact ? 18 : 20,
            icon: Icon(
              Icons.edit_outlined,
              color: busy ? AppColors.textSecondary : AppColors.primary,
            ),
          ),
        IconButton(
          tooltip: 'Печать ценника',
          onPressed: busy ? null : onPrint,
          padding: EdgeInsets.zero,
          constraints: iconConstraints,
          iconSize: compact ? 18 : 20,
          icon: Icon(
            Icons.print_outlined,
            color: busy ? AppColors.textSecondary : AppColors.accent,
          ),
        ),
        if (showAdminActions)
          IconButton(
            tooltip: 'Удалить черновик',
            onPressed: busy ? null : onDelete,
            padding: EdgeInsets.zero,
            constraints: iconConstraints,
            iconSize: compact ? 18 : 20,
            icon: Icon(
              Icons.delete_outline,
              color: busy ? AppColors.textSecondary : AppColors.saleRed,
            ),
          ),
      ],
    );
  }
}

class _DraftThumbnail extends StatelessWidget {
  const _DraftThumbnail({
    this.url,
    this.size = 48,
    this.onTap,
  });

  final String? url;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final resolved = url?.trim();
    if (resolved == null || resolved.isEmpty) {
      return _placeholder();
    }
    return AdminClickableNetworkThumbnail(
      imageUrl: resolved,
      size: size,
      onTap: onTap,
    );
  }

  Widget _placeholder() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Icon(
        Icons.image_not_supported_outlined,
        size: 22,
        color: AppColors.textSecondary,
      ),
    );
  }
}

class _DraftAcceptPreviewDialog extends StatefulWidget {
  const _DraftAcceptPreviewDialog({
    required this.row,
    required this.sku,
  });

  final Map<String, dynamic> row;
  final String sku;

  static const _presetTypes = [
    'Кольцо',
    'Серьги',
    'Цепь',
    'Браслет',
    'Подвеска',
    'Колье',
    'Другое',
  ];

  @override
  State<_DraftAcceptPreviewDialog> createState() =>
      _DraftAcceptPreviewDialogState();
}

class _DraftAcceptPreviewDialogState extends State<_DraftAcceptPreviewDialog> {
  late String _selectedType;
  final _customNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final existing = widget.row['notes']?.toString().trim() ?? '';
    if (existing.isNotEmpty &&
        _DraftAcceptPreviewDialog._presetTypes.contains(existing)) {
      _selectedType = existing;
    } else if (existing.isNotEmpty) {
      _selectedType = 'Другое';
      _customNameController.text = existing;
    } else {
      _selectedType = _DraftAcceptPreviewDialog._presetTypes.first;
    }
  }

  @override
  void dispose() {
    _customNameController.dispose();
    super.dispose();
  }

  String get _resolvedName {
    if (_selectedType == 'Другое') {
      return _customNameController.text.trim();
    }
    return _selectedType;
  }

  JewelryLabelData get _previewData {
    final merged = Map<String, dynamic>.from(widget.row)
      ..['notes'] = _resolvedName.isEmpty ? widget.sku : _resolvedName;
    return JewelryLabelData.fromProductMap(merged);
  }

  void _accept() {
    final name = _resolvedName;
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Укажите наименование изделия')),
      );
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Приёмка · ${widget.sku}',
        style: AppTypography.heading(fontSize: 18),
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _selectedType,
                decoration: const InputDecoration(
                  labelText: 'Наименование изделия',
                  border: OutlineInputBorder(),
                ),
                items: _DraftAcceptPreviewDialog._presetTypes
                    .map(
                      (type) => DropdownMenuItem(
                        value: type,
                        child: Text(type),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedType = value);
                },
              ),
              if (_selectedType == 'Другое') ...[
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
              JewelryLabelPreview(data: _previewData),
              const SizedBox(height: 12),
              Text(
                'Наименование сохранится в notes и попадёт на бирку.',
                style: AppTypography.productMeta(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _accept,
          child: const Text('Принять и печатать'),
        ),
      ],
    );
  }
}

class _DraftBatchReconcileDialog extends StatelessWidget {
  const _DraftBatchReconcileDialog({
    required this.report,
    required this.scopeSubtitle,
    required this.totalRows,
  });

  final DraftBatchReconcileReport report;
  final String scopeSubtitle;
  final int totalRows;

  Future<void> _copyReport(BuildContext context) async {
    final text = draftBatchReconcilePlainText(
      report: report,
      scopeSubtitle: scopeSubtitle,
      totalRows: totalRows,
    );
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Отчёт скопирован'),
        backgroundColor: AppColors.accent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _groupCard({
    required String title,
    required DraftBatchGroupTotals stats,
    required Color accent,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTypography.heading(fontSize: 16).copyWith(color: accent),
          ),
          const SizedBox(height: 8),
          _metricLine('Количество изделий', '${stats.count} шт.'),
          _metricLine(
            'Суммарный вес',
            '${stats.weightGrams.toStringAsFixed(2)} г',
          ),
          _metricLine('Сумма', formatDraftReconcileKrw(stats.priceKrw)),
        ],
      ),
    );
  }

  Widget _metricLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: AppTypography.productMeta()),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: AppTypography.productMeta().copyWith(
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final dialogWidth = width < 520 ? width * 0.92 : 520.0;
    final grand = report.grandTotal;
    const goldAccent = AppColors.bannerGoldEnd;
    const silverAccent = Color(0xFF6B7280);

    return Dialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.accent, width: 1.5),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: dialogWidth, maxHeight: 640),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.bannerGoldStart,
                    AppColors.bannerGoldEnd,
                  ],
                ),
                borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Сверка партии',
                    style: AppTypography.heading(fontSize: 20).copyWith(
                      color: AppColors.textOnAccent,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    scopeSubtitle,
                    style: AppTypography.productMeta().copyWith(
                      color: AppColors.textOnAccent.withValues(alpha: 0.92),
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    'Позиций в списке: $totalRows',
                    style: AppTypography.productMeta().copyWith(
                      color: AppColors.textOnAccent.withValues(alpha: 0.85),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _groupCard(
                      title: 'Золото',
                      stats: report.gold,
                      accent: goldAccent,
                    ),
                    const SizedBox(height: 10),
                    _groupCard(
                      title: 'Серебро',
                      stats: report.silver,
                      accent: silverAccent,
                    ),
                    if (report.other.count > 0) ...[
                      const SizedBox(height: 10),
                      _groupCard(
                        title: 'Прочее / Не указано',
                        stats: report.other,
                        accent: AppColors.textSecondary,
                      ),
                    ],
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.cardBackground,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.accent, width: 1.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Итого по партии',
                            style: AppTypography.heading(fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          _metricLine(
                            'Общее количество',
                            '${grand.count} шт.',
                          ),
                          _metricLine(
                            'Общий вес',
                            '${grand.weightGrams.toStringAsFixed(2)} г',
                          ),
                          const SizedBox(height: 4),
                          Text(
                            formatDraftReconcileKrw(grand.priceKrw),
                            style: AppTypography.heading(fontSize: 22).copyWith(
                              color: AppColors.bannerGoldEnd,
                            ),
                            textAlign: TextAlign.right,
                          ),
                          Text(
                            'Общая сумма',
                            style: AppTypography.productMeta(),
                            textAlign: TextAlign.right,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _copyReport(context),
                      icon: const Icon(Icons.copy_outlined, size: 18),
                      label: const Text('Копировать отчёт'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.accent),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.textOnAccent,
                      ),
                      child: const Text('Закрыть'),
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
