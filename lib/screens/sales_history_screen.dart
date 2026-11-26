import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../core/utils/won_format.dart';
import '../core/widgets/krw_text.dart';
import '../features/admin/presentation/widgets/admin_pos_cart_sheet.dart';
import '../features/admin/presentation/widgets/admin_toast.dart';
import '../features/admin/presentation/widgets/admin_product_photo_preview.dart';
import '../models/sales_history_row.dart';
import '../services/sales_history_service.dart';

DateTime _kstNow() => DateTime.now().toUtc().add(const Duration(hours: 9));

String _isoDateKst(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

DateTimeRange defaultSalesHistoryRangeKst() {
  final kst = _kstNow();
  final start = DateTime(kst.year, kst.month, kst.day);
  final end = DateTime(kst.year, kst.month, kst.day);
  return DateTimeRange(start: start, end: end);
}

String formatSalesRangeLabel(DateTimeRange range) {
  final fmt = DateFormat('d MMM y', 'ru');
  return '${fmt.format(range.start)} — ${fmt.format(range.end)}';
}

String formatSoldAtKst(SalesHistoryRow row) {
  final utc = row.soldAtUtc;
  if (utc != null) {
    final kst = utc.add(const Duration(hours: 9));
    return DateFormat('yyyy-MM-dd HH:mm').format(kst);
  }
  final dateOnly = row.soldDateKst?.trim();
  if (dateOnly != null && dateOnly.isNotEmpty) return dateOnly;
  return '—';
}

String salesStorePointLabel(String? code) {
  final raw = code?.trim().toUpperCase() ?? '';
  if (raw == 'ICN') return 'Инчхон (ICN)';
  if (raw == 'ANS') return 'Ансан (ANS)';
  return '—';
}

String? metalCategoryBadgeLabel(String? category) {
  final raw = category?.trim().toLowerCase() ?? '';
  if (raw.isEmpty) return null;
  if (raw == 'gold' || raw.contains('золот')) return 'Золото';
  if (raw == 'silver' || raw.contains('сереб')) return 'Серебро';
  return null;
}

String formatWeightGrams(double? grams) {
  if (grams == null || grams <= 0) return '';
  return '${grams.toStringAsFixed(2)} г';
}

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({
    super.key,
    this.repository,
    this.onProductReturned,
  });

  final SalesHistoryRepository? repository;
  final VoidCallback? onProductReturned;

  @override
  State<SalesHistoryScreen> createState() => SalesHistoryScreenState();
}

class SalesHistoryScreenState extends State<SalesHistoryScreen> {
  late final SalesHistoryRepository _repo;
  final _scrollController = ScrollController();
  final _rows = <SalesHistoryRow>[];

  late DateTimeRange _selectedRange;
  SalesHistoryStoreFilter _storeFilter = SalesHistoryStoreFilter.all;
  final _sellerController = TextEditingController();
  Timer? _sellerDebounce;
  SalesHistorySummary? _summary;
  bool _kpiLoading = false;
  bool _listLoading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _pageIndex = 0;
  String? _error;
  String? _returnBusyKey;
  Set<String> _reversedLegacyIds = const {};

  String get _rangeStartIso => _isoDateKst(_selectedRange.start);
  String get _rangeEndIso => _isoDateKst(_selectedRange.end);

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? SalesHistoryRepository();
    _selectedRange = defaultSalesHistoryRangeKst();
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _sellerDebounce?.cancel();
    _sellerController.dispose();
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  void reload() {
    if (!mounted) return;
    _loadInitial();
  }

  void _recomputeReversalIndex() {
    _reversedLegacyIds = SalesHistoryRow.collectReversedLegacyIds(_rows);
  }

  bool _canShowReturnButton(SalesHistoryRow row) {
    if (!row.canReturn) return false;
    if (_reversedLegacyIds.contains(row.legacyId)) return false;
    return true;
  }

  bool _showReturnedBadge(SalesHistoryRow row) {
    return row.isPwaSale &&
        !row.isReturnLine &&
        _reversedLegacyIds.contains(row.legacyId);
  }

  Future<void> _loadInitial() async {
    setState(() {
      _listLoading = true;
      _kpiLoading = true;
      _error = null;
      _rows.clear();
      _pageIndex = 0;
      _hasMore = true;
      _reversedLegacyIds = const {};
      _summary = null;
    });

    try {
      final store = _storeFilter.rpcValue;
      final summary = await _repo.fetchSummary(
        soldDateKstStart: _rangeStartIso,
        soldDateKstEnd: _rangeEndIso,
        store: store,
        sellerName: _sellerController.text,
      );
      final page = await _repo.fetchPage(
        pageIndex: 0,
        soldDateKstStart: _rangeStartIso,
        soldDateKstEnd: _rangeEndIso,
        store: store,
      );
      _rows
        ..clear()
        ..addAll(page);
      _recomputeReversalIndex();
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _hasMore = page.length >= SalesHistoryRepository.defaultPageSize;
        _pageIndex = 1;
        _listLoading = false;
        _kpiLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _listLoading = false;
        _kpiLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _listLoading) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _repo.fetchPage(
        pageIndex: _pageIndex,
        soldDateKstStart: _rangeStartIso,
        soldDateKstEnd: _rangeEndIso,
        store: _storeFilter.rpcValue,
      );
      _rows.addAll(page);
      _recomputeReversalIndex();
      if (!mounted) return;
      setState(() {
        _hasMore = page.length >= SalesHistoryRepository.defaultPageSize;
        _pageIndex += 1;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingMore = false;
        _error = error.toString();
      });
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.maxScrollExtent <= 0) return;
    if (pos.pixels >= pos.maxScrollExtent - 280) {
      _loadMore();
    }
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _selectedRange,
      locale: const Locale('ru', 'RU'),
      helpText: 'Период продаж (KST)',
    );
    if (picked == null || !mounted) return;
    setState(() => _selectedRange = picked);
    await _loadInitial();
  }

  void _onSellerChanged(String _) {
    _sellerDebounce?.cancel();
    _sellerDebounce = Timer(const Duration(milliseconds: 400), _loadInitial);
  }

  void _onStoreChanged(SalesHistoryStoreFilter next) {
    if (next.rpcValue == _storeFilter.rpcValue) return;
    setState(() => _storeFilter = next);
    _loadInitial();
  }

  void _snack(String message, {bool error = false}) {
    showAdminToast(context, message, error: error);
  }

  Future<void> _openPosReturnDialog(SalesHistoryRow row) async {
    if (!_canShowReturnButton(row)) {
      _snack('Возврат недоступен для этой продажи', error: true);
      return;
    }

    final productId = row.resolvedProductId;
    if (productId == null || productId.isEmpty) {
      _snack('Не найден product_id для возврата', error: true);
      return;
    }

    final result = await showDialog<_PosReturnFormData>(
      context: context,
      builder: (context) => _PosReturnDialog(
        sku: row.sku,
        productId: productId,
      ),
    );
    if (result == null || !mounted) return;

    setState(() => _returnBusyKey = row.legacyId);
    try {
      await _repo.processPosProductReturn(
        productId: productId,
        reason: result.reason,
        adminName: result.adminName,
      );
      if (!mounted) return;
      setState(() => _returnBusyKey = null);
      _snack('Товар успешно возвращен на витрину!');
      widget.onProductReturned?.call();
      await _loadInitial();
    } catch (error) {
      if (!mounted) return;
      setState(() => _returnBusyKey = null);
      final message = error is StateError
          ? error.message
          : error.toString().replaceFirst('Exception: ', '');
      _snack(message, error: true);
    }
  }

  Future<void> _openPhotoPreview(SalesHistoryRow row) async {
    final url = row.imageUrl?.trim();
    if (url == null || url.isEmpty) return;
    final title = row.sku.isNotEmpty ? row.sku : row.productName ?? 'Фото';
    await showAdminProductPhotoPreview(
      context,
      title: title,
      subtitle: row.productName,
      imageUrls: [url],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _KpiHeader(
            rangeLabel: formatSalesRangeLabel(_selectedRange),
            storeFilter: _storeFilter,
            sellerController: _sellerController,
            summary: _summary,
            loading: _kpiLoading,
            onPickRange: _pickDateRange,
            onStoreChanged: _onStoreChanged,
            onSellerChanged: _onSellerChanged,
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                _error!,
                style: AppTypography.productMeta().copyWith(color: AppColors.saleRed),
              ),
            ),
          Expanded(
            child: _listLoading && _rows.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _loadInitial,
                    child: ListView.builder(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: _rows.length + (_hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= _rows.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        final row = _rows[index];
                        return _SalesHistoryTile(
                          row: row,
                          returnBusy: _returnBusyKey == row.legacyId,
                          showReturnedBadge: _showReturnedBadge(row),
                          onPhotoTap: () => _openPhotoPreview(row),
                          onReturn: _canShowReturnButton(row)
                              ? () => _openPosReturnDialog(row)
                              : null,
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

int _drawerKrw(SalesHistorySummary? summary) {
  if (summary == null) return 0;
  if (summary.hasShiftCash) return summary.shiftCashKrw;
  if (summary.tradeInScrapKrw > 0) return summary.netCashKrw;
  return summary.totalSumKrw;
}

List<String> _methodOrder(Map<String, int> methods) {
  const preferred = ['cash', 'card', 'transfer', 'unknown'];
  final rest = methods.keys.where((key) => !preferred.contains(key)).toList()
    ..sort();
  return [...preferred.where(methods.containsKey), ...rest];
}

String _methodLabel(String method) {
  if (method == 'unknown') return 'Прочее';
  return AdminPosPaymentMethods.label(method);
}

class _KpiHeader extends StatelessWidget {
  const _KpiHeader({
    required this.rangeLabel,
    required this.storeFilter,
    required this.sellerController,
    required this.summary,
    required this.loading,
    required this.onPickRange,
    required this.onStoreChanged,
    required this.onSellerChanged,
  });

  final String rangeLabel;
  final SalesHistoryStoreFilter storeFilter;
  final TextEditingController sellerController;
  final SalesHistorySummary? summary;
  final bool loading;
  final VoidCallback onPickRange;
  final void Function(SalesHistoryStoreFilter) onStoreChanged;
  final ValueChanged<String> onSellerChanged;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.92),
            AppColors.accent.withValues(alpha: 0.85),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.18),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: onPickRange,
                icon: const Icon(Icons.date_range_outlined, size: 18),
                label: Text(
                  rangeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textOnPrimary,
                  side: BorderSide(color: AppColors.textOnPrimary.withValues(alpha: 0.6)),
                ),
              ),
              _StoreSegmentedControl(
                selected: storeFilter,
                onChanged: onStoreChanged,
              ),
              SizedBox(
                width: 240,
                child: TextField(
                  controller: sellerController,
                  onChanged: onSellerChanged,
                  style: const TextStyle(color: AppColors.textOnPrimary),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'Касса: продавец (имя или код)',
                    hintStyle: TextStyle(
                      color: AppColors.textOnPrimary.withValues(alpha: 0.7),
                      fontSize: 13,
                    ),
                    prefixIcon: const Icon(
                      Icons.person_outline,
                      color: AppColors.textOnPrimary,
                      size: 18,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: AppColors.textOnPrimary.withValues(alpha: 0.5),
                      ),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.textOnPrimary),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'Отчёт за период (KST)',
            style: AppTypography.caption(
              color: AppColors.textOnPrimary,
              fontWeight: FontWeight.w600,
            ).copyWith(fontSize: 14),
          ),
          const SizedBox(height: 8),
          if (loading)
            const SizedBox(
              height: 80,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
              ),
            )
          else ...[
            KrwText(
              amount: _drawerKrw(s),
              style: AppTypography.heading(fontSize: 30).copyWith(
                color: AppColors.textOnPrimary,
                letterSpacing: -0.5,
              ),
              digitStyle: AppTypography.heading(fontSize: 30).copyWith(
                color: AppColors.textOnPrimary,
                letterSpacing: -0.5,
              ),
              currencyColor: AppColors.textOnPrimary,
            ),
            const SizedBox(height: 6),
            Text(
              s?.hasShiftCash == true
                  ? 'Касса смены'
                  : ((s?.tradeInScrapKrw ?? 0) > 0
                      ? 'Фактически в кассу (чистая выручка)'
                      : 'Сумма продаж'),
              style: AppTypography.productMeta().copyWith(
                color: AppColors.textOnPrimary.withValues(alpha: 0.88),
                fontSize: 11,
              ),
            ),
            if (s?.hasShiftCash == true || (s?.tradeInScrapKrw ?? 0) > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Продано изделий: ${formatWon(s?.grossSalesKrw ?? s?.totalSumKrw ?? 0)}',
                style: AppTypography.productMeta().copyWith(
                  color: AppColors.textOnPrimary.withValues(alpha: 0.92),
                ),
              ),
            ],
            if ((s?.reservationCashKrw ?? 0) != 0) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Text(
                    'Залоги и доплаты: ',
                    style: AppTypography.productMeta().copyWith(
                      color: AppColors.textOnPrimary.withValues(alpha: 0.92),
                    ),
                  ),
                  KrwText(
                    amount: s!.reservationCashKrw,
                    showPlusSign: s.reservationCashKrw > 0,
                    style: AppTypography.productMeta().copyWith(
                      color: AppColors.textOnPrimary.withValues(alpha: 0.92),
                    ),
                    digitStyle: AppTypography.productMeta().copyWith(
                      color: AppColors.textOnPrimary.withValues(alpha: 0.92),
                    ),
                    currencyColor: AppColors.textOnPrimary,
                  ),
                ],
              ),
            ],
            if ((s?.tradeInScrapKrw ?? 0) > 0) ...[
              const SizedBox(height: 4),
              Text(
                sellerController.text.trim().isEmpty
                    ? 'Зачтено ломом (${s?.tradeInBatchCount ?? 0}): ${formatWon(-(s?.tradeInScrapKrw ?? 0))}'
                    : 'Зачтено ломом: ${formatWon(-(s?.tradeInScrapKrw ?? 0))}',
                style: AppTypography.productMeta().copyWith(
                  color: AppColors.textOnPrimary.withValues(alpha: 0.92),
                ),
              ),
            ],
            if (s?.hasShiftCash == true && (s?.byMethod.isNotEmpty ?? false)) ...[
              const SizedBox(height: 8),
              for (final method in _methodOrder(s!.byMethod))
                if ((s.byMethod[method] ?? 0) != 0)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Row(
                      children: [
                        Text(
                          '${_methodLabel(method)}: ',
                          style: AppTypography.productMeta().copyWith(
                            color: AppColors.textOnPrimary.withValues(alpha: 0.92),
                            fontSize: 12,
                          ),
                        ),
                        KrwText(
                          amount: s.byMethod[method] ?? 0,
                          style: AppTypography.productMeta().copyWith(
                            color: AppColors.textOnPrimary,
                            fontSize: 12,
                          ),
                          digitStyle: AppTypography.productMeta().copyWith(
                            color: AppColors.textOnPrimary,
                            fontSize: 12,
                          ),
                          currencyColor: AppColors.textOnPrimary,
                        ),
                      ],
                    ),
                  ),
            ],
            if (sellerController.text.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Касса отфильтрована по продавцу. Список продаж и металл — по всем.',
                  style: AppTypography.productMeta().copyWith(
                    color: AppColors.textOnPrimary.withValues(alpha: 0.8),
                    fontSize: 11,
                  ),
                ),
              ),
            const SizedBox(height: 2),
            Text(
              '${s?.totalCount ?? 0} поз.',
              style: AppTypography.productMeta().copyWith(
                color: AppColors.textOnPrimary.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(height: 14),
            _MetalKpiLine(
              title: 'Золото',
              weightGrams: s?.goldWeightGrams ?? 0,
              sumKrw: s?.goldSumKrw ?? 0,
              count: s?.goldCount ?? 0,
            ),
            const SizedBox(height: 8),
            _MetalKpiLine(
              title: 'Серебро',
              weightGrams: s?.silverWeightGrams ?? 0,
              sumKrw: s?.silverSumKrw ?? 0,
              count: s?.silverCount ?? 0,
            ),
            if ((s?.otherCount ?? 0) > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Прочее: ${s!.otherCount} поз.',
                style: AppTypography.productMeta().copyWith(
                  color: AppColors.textOnPrimary.withValues(alpha: 0.85),
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _StoreSegmentedControl extends StatelessWidget {
  const _StoreSegmentedControl({
    required this.selected,
    required this.onChanged,
  });

  final SalesHistoryStoreFilter selected;
  final void Function(SalesHistoryStoreFilter) onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'ALL', label: Text('Все')),
        ButtonSegment(value: 'ICN', label: Text('Инчхон (ICN)')),
        ButtonSegment(value: 'ANS', label: Text('Ансан (ANS)')),
      ],
      selected: {selected.rpcValue},
      onSelectionChanged: (set) {
        final value = set.first;
        for (final filter in SalesHistoryStoreFilter.values) {
          if (filter.rpcValue == value) {
            onChanged(filter);
            return;
          }
        }
      },
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        foregroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary;
          }
          return AppColors.textOnPrimary;
        }),
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.textOnPrimary;
          }
          return AppColors.textOnPrimary.withValues(alpha: 0.12);
        }),
        side: WidgetStateProperty.all(
          BorderSide(color: AppColors.textOnPrimary.withValues(alpha: 0.45)),
        ),
      ),
    );
  }
}

class _MetalKpiLine extends StatelessWidget {
  const _MetalKpiLine({
    required this.title,
    required this.weightGrams,
    required this.sumKrw,
    required this.count,
  });

  final String title;
  final double weightGrams;
  final int sumKrw;
  final int count;

  @override
  Widget build(BuildContext context) {
    final weightText =
        weightGrams > 0 ? '${weightGrams.toStringAsFixed(2)} г · ' : '';
    return Text(
      '$title: $weightText${formatWon(sumKrw)} · $count шт.',
      style: AppTypography.productMeta().copyWith(
        color: AppColors.textOnPrimary.withValues(alpha: 0.92),
        fontWeight: FontWeight.w500,
      ),
    );
  }
}

class _SalesHistoryTile extends StatelessWidget {
  const _SalesHistoryTile({
    required this.row,
    required this.onPhotoTap,
    this.onReturn,
    this.returnBusy = false,
    this.showReturnedBadge = false,
  });

  final SalesHistoryRow row;
  final VoidCallback onPhotoTap;
  final VoidCallback? onReturn;
  final bool returnBusy;
  final bool showReturnedBadge;

  @override
  Widget build(BuildContext context) {
    final name = row.productName?.trim();
    final showName = name != null && name.isNotEmpty && name != row.sku;
    final weightText = formatWeightGrams(row.weightGrams);
    final metal = metalCategoryBadgeLabel(row.metalCategory);
    final payment = row.paymentMethod?.trim();
    final paymentLabel = payment != null && payment.isNotEmpty
        ? AdminPosPaymentMethods.label(payment)
        : '—';
    final seller = row.sellerName?.trim();
    final manufacturer = row.manufacturer?.trim();
    final soldAt = formatSoldAtKst(row);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SaleThumb(url: row.imageUrl, onTap: onPhotoTap),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.sku.isEmpty ? '—' : row.sku,
                      style: AppTypography.productName(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (showName) ...[
                      const SizedBox(height: 2),
                      Text(
                        name,
                        style: AppTypography.productMeta(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (weightText.isNotEmpty)
                          _InfoChip(
                            icon: Icons.scale_outlined,
                            label: weightText,
                          ),
                        if (metal != null)
                          _InfoChip(
                            icon: Icons.diamond_outlined,
                            label: metal,
                            emphasized: true,
                          ),
                        _InfoChip(
                          icon: Icons.store_outlined,
                          label: salesStorePointLabel(row.storeLocation),
                        ),
                        if (manufacturer != null && manufacturer.isNotEmpty)
                          _InfoChip(
                            icon: Icons.factory_outlined,
                            label: manufacturer,
                          ),
                        _InfoChip(
                          icon: Icons.person_outline,
                          label: (seller != null && seller.isNotEmpty)
                              ? seller
                              : '—',
                        ),
                        _InfoChip(
                          icon: Icons.payments_outlined,
                          label: paymentLabel,
                        ),
                        _InfoChip(
                          icon: Icons.schedule,
                          label: soldAt,
                        ),
                        if (row.isTradeIn && row.scrapTradeInKrw > 0)
                          _InfoChip(
                            icon: Icons.recycling_outlined,
                            label: 'С ломом (Trade-In)',
                            emphasized: true,
                          ),
                      ],
                    ),
                    if (row.isTradeIn && row.scrapTradeInKrw > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Лом: ${formatWon(-row.scrapTradeInKrw)}',
                        style: AppTypography.productMeta().copyWith(
                          color: AppColors.saleRed,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (row.netCashDeltaKrw != null)
                        Text(
                          row.netCashDeltaKrw! > 0
                              ? 'Получено от клиента: ${formatWonDelta(row.netCashDeltaKrw!)}'
                              : row.netCashDeltaKrw! < 0
                                  ? 'Доплачено покупателю: ${formatWon(-row.netCashDeltaKrw!.abs())}'
                                  : 'Обмен без доплаты',
                          style: AppTypography.productMeta(),
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _SalePriceColumn(
                row: row,
                onReturn: onReturn,
                returnBusy: returnBusy,
                showReturnedBadge: showReturnedBadge,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    this.emphasized = false,
  });

  final IconData icon;
  final String label;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final bg = emphasized
        ? AppColors.accent.withValues(alpha: 0.12)
        : AppColors.background;
    final fg = emphasized ? AppColors.accent : AppColors.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border.withValues(alpha: 0.8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 200),
            child: Text(
              label,
              style: AppTypography.productMeta().copyWith(
                fontSize: 11,
                color: fg,
                fontWeight: emphasized ? FontWeight.w600 : FontWeight.w400,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _SalePriceColumn extends StatelessWidget {
  const _SalePriceColumn({
    required this.row,
    this.onReturn,
    this.returnBusy = false,
    this.showReturnedBadge = false,
  });

  final SalesHistoryRow row;
  final VoidCallback? onReturn;
  final bool returnBusy;
  final bool showReturnedBadge;

  @override
  Widget build(BuildContext context) {
    final showsDiscount = row.showsDiscount;
    final discountPct = row.discountPercent > 0
        ? row.discountPercent
        : (row.listPriceKrw != null && row.listPriceKrw! > row.priceKrw
            ? (((row.listPriceKrw! - row.priceKrw) / row.listPriceKrw!) * 100)
                .round()
            : 0);

    return SizedBox(
      width: 118,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (showsDiscount) ...[
            KrwText(
              amount: row.displayListPriceKrw,
              style: AppTypography.productMeta().copyWith(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
              digitStyle: AppTypography.productMeta().copyWith(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
              decoration: TextDecoration.lineThrough,
              decorationColor: AppColors.textSecondary,
            ),
            if (discountPct > 0)
              Container(
                margin: const EdgeInsets.only(top: 2, bottom: 2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.saleRed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '-$discountPct%',
                  style: AppTypography.productMeta().copyWith(
                    fontSize: 11,
                    color: AppColors.saleRed,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
          KrwText(
            amount: row.priceKrw,
            style: AppTypography.price(fontSize: 17).copyWith(
              color: row.isReturnLine ? AppColors.saleRed : null,
            ),
            digitStyle: AppTypography.price(fontSize: 17).copyWith(
              color: row.isReturnLine ? AppColors.saleRed : null,
            ),
            textAlign: TextAlign.end,
          ),
          if (row.isTradeIn &&
              row.scrapTradeInKrw > 0 &&
              row.netCashDeltaKrw != null) ...[
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: KrwText(
                amount: row.netCashDeltaKrw!,
                showPlusSign: row.netCashDeltaKrw! > 0,
                currencyColor: AppColors.currencyWonAccent,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.saleRed,
                ),
                digitStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.saleRed,
                ),
                textAlign: TextAlign.end,
              ),
            ),
          ],
          if (showReturnedBadge) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Возвращено',
                style: AppTypography.productMeta().copyWith(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          if (onReturn != null) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 32,
              child: returnBusy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton(
                      onPressed: onReturn,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Возврат',
                        style: AppTypography.productMeta().copyWith(
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600,
                          fontSize: 11,
                        ),
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PosReturnFormData {
  const _PosReturnFormData({required this.reason, required this.adminName});

  final String reason;
  final String adminName;
}

class _PosReturnDialog extends StatefulWidget {
  const _PosReturnDialog({
    required this.sku,
    required this.productId,
  });

  final String sku;
  final String productId;

  @override
  State<_PosReturnDialog> createState() => _PosReturnDialogState();
}

class _PosReturnDialogState extends State<_PosReturnDialog> {
  final _reasonController = TextEditingController();
  final _adminController = TextEditingController(text: 'Администратор');
  String? _error;

  static const _reasonPresets = [
    'Передумал',
    'Брак',
    'Размер не подошёл',
  ];

  @override
  void dispose() {
    _reasonController.dispose();
    _adminController.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _reasonController.text.trim();
    final admin = _adminController.text.trim();
    if (reason.isEmpty || admin.isEmpty) {
      setState(() => _error = 'Заполните причину и имя администратора');
      return;
    }
    Navigator.pop(
      context,
      _PosReturnFormData(reason: reason, adminName: admin),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Возврат товара',
        style: AppTypography.heading(fontSize: 20),
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'SKU ${widget.sku}',
                style: AppTypography.productName(),
              ),
              const SizedBox(height: 4),
              Text(
                'ID ${widget.productId}',
                style: AppTypography.productMeta(),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _reasonController,
                decoration: const InputDecoration(
                  labelText: 'Причина возврата',
                  hintText: 'Например: Передумал',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.sentences,
                maxLines: 2,
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _reasonPresets.map((preset) {
                  return ActionChip(
                    label: Text(preset),
                    onPressed: () {
                      _reasonController.text = preset;
                      setState(() => _error = null);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _adminController,
                decoration: const InputDecoration(
                  labelText: 'Администратор / кассир',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: AppTypography.productMeta().copyWith(
                    color: AppColors.saleRed,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.assignment_return_outlined),
          label: const Text('Оформить возврат'),
        ),
      ],
    );
  }
}

class _SaleThumb extends StatelessWidget {
  const _SaleThumb({this.url, required this.onTap});

  final String? url;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const size = 60.0;
    final hasUrl = url != null && url!.isNotEmpty;

    Widget child;
    if (!hasUrl) {
      child = Container(
        color: AppColors.background,
        alignment: Alignment.center,
        child: Icon(
          Icons.image_not_supported_outlined,
          color: AppColors.textSecondary.withValues(alpha: 0.5),
        ),
      );
    } else {
      child = Image.network(
        url!,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            color: AppColors.background,
            alignment: Alignment.center,
            child: const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        },
        errorBuilder: (_, _, _) => Container(
          color: AppColors.background,
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image_outlined, size: 22),
        ),
      );
    }

    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: hasUrl ? onTap : null,
        child: SizedBox(
          width: size,
          height: size,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}