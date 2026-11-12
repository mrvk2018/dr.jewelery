import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../core/utils/won_format.dart';
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
  final start = DateTime(kst.year, kst.month, 1);
  final end = DateTime(kst.year, kst.month, kst.day);
  return DateTimeRange(start: start, end: end);
}

String formatSalesRangeLabel(DateTimeRange range) {
  final fmt = DateFormat('d MMM y', 'ru');
  return '${fmt.format(range.start)} — ${fmt.format(range.end)}';
}

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key, this.repository});

  final SalesHistoryRepository? repository;

  @override
  State<SalesHistoryScreen> createState() => SalesHistoryScreenState();
}

class SalesHistoryScreenState extends State<SalesHistoryScreen> {
  late final SalesHistoryRepository _repo;
  final _scrollController = ScrollController();
  final _rows = <SalesHistoryRow>[];

  late DateTimeRange _selectedRange;
  int? _periodRevenueKrw;
  bool _kpiLoading = false;
  bool _listLoading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _pageIndex = 0;
  String? _error;
  String? _returnBusyKey;
  Set<String> _reversedLegacyIds = const {};
  Map<String, String> _latestSaleLegacyByProductId = const {};
  Map<String, String> _productStatusById = const {};

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
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  /// Повторная загрузка списка и KPI с текущим [_selectedRange] (IndexedStack / после POS).
  void reload() {
    if (!mounted) return;
    _loadInitial();
  }

  void _recomputeReversalIndex() {
    _reversedLegacyIds = SalesHistoryRow.collectReversedLegacyIds(_rows);
    _latestSaleLegacyByProductId =
        SalesHistoryRow.latestPwaSaleLegacyByProductId(_rows);
  }

  Future<Map<String, String>> _fetchProductStatusesForRows() {
    return _repo.fetchProductStatusesByIds(
      SalesHistoryRow.pwaProductIdsFromRows(_rows),
    );
  }

  bool _canShowReturnButton(SalesHistoryRow row) {
    if (!row.canProcessPosReturn) return false;
    if (_reversedLegacyIds.contains(row.legacyId)) return false;
    final productId = row.resolvedProductId;
    if (productId == null || productId.isEmpty) return false;
    final latestLegacy = _latestSaleLegacyByProductId[productId];
    if (latestLegacy != row.legacyId) return false;
    return _productStatusById[productId] == 'sold';
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
      _latestSaleLegacyByProductId = const {};
      _productStatusById = const {};
    });

    try {
      final revenue = await _repo.sumPriceKrwForSoldDateRangeKst(
        _rangeStartIso,
        _rangeEndIso,
      );
      final page = await _repo.fetchPage(
        pageIndex: 0,
        soldDateKstStart: _rangeStartIso,
        soldDateKstEnd: _rangeEndIso,
      );
      _rows
        ..clear()
        ..addAll(page);
      _recomputeReversalIndex();
      final productStatuses =
          await _fetchProductStatusesForRows();
      if (!mounted) return;
      setState(() {
        _periodRevenueKrw = revenue;
        _hasMore = page.length >= SalesHistoryRepository.defaultPageSize;
        _pageIndex = 1;
        _productStatusById = productStatuses;
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
      );
      _rows.addAll(page);
      _recomputeReversalIndex();
      final newStatuses = await _repo.fetchProductStatusesByIds(
        SalesHistoryRow.pwaProductIdsFromRows(page),
      );
      if (!mounted) return;
      setState(() {
        _productStatusById = {..._productStatusById, ...newStatuses};
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

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.saleRed : AppColors.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _openPosReturnDialog(SalesHistoryRow row) async {
    if (!_canShowReturnButton(row)) {
      _snack(
        'Возврат недоступен для этой продажи (legacy ${row.legacyId})',
        error: true,
      );
      return;
    }

    final productId = row.resolvedProductId!;
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

  void _showPayloadDialog(SalesHistoryRow row) {
    final payload = row.rawLegacyPayload;
    final text = payload == null
        ? 'raw_legacy_payload отсутствует'
        : const JsonEncoder.withIndent('  ').convert(payload);

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Аудит · legacy ${row.legacyId}', style: AppTypography.heading(fontSize: 18)),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: SelectableText(
              text,
              style: AppTypography.productMeta().copyWith(
                fontFamily: 'monospace',
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
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
            revenueKrw: _periodRevenueKrw,
            loading: _kpiLoading,
            onPickRange: _pickDateRange,
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
                          onTap: () => _showPayloadDialog(row),
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

class _KpiHeader extends StatelessWidget {
  const _KpiHeader({
    required this.rangeLabel,
    required this.revenueKrw,
    required this.loading,
    required this.onPickRange,
  });

  final String rangeLabel;
  final int? revenueKrw;
  final bool loading;
  final VoidCallback onPickRange;

  @override
  Widget build(BuildContext context) {
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Выручка за период (KST)',
                  style: AppTypography.caption(
                    color: AppColors.textOnPrimary,
                    fontWeight: FontWeight.w600,
                  ).copyWith(fontSize: 14),
                ),
              ),
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
            ],
          ),
          const SizedBox(height: 12),
          if (loading)
            const SizedBox(
              height: 36,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
              ),
            )
          else
            Text(
              formatWon(revenueKrw ?? 0),
              style: AppTypography.heading(fontSize: 32).copyWith(
                color: AppColors.textOnPrimary,
                letterSpacing: -0.5,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            'Сумма price_krw за выбранный период (sold_date_kst)',
            style: AppTypography.productMeta().copyWith(
              color: AppColors.textOnPrimary.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}

class _SalesHistoryTile extends StatelessWidget {
  const _SalesHistoryTile({
    required this.row,
    required this.onTap,
    this.onReturn,
    this.returnBusy = false,
    this.showReturnedBadge = false,
  });

  final SalesHistoryRow row;
  final VoidCallback onTap;
  final VoidCallback? onReturn;
  final bool returnBusy;
  final bool showReturnedBadge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                _Thumb(url: row.imageUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.sku.isEmpty ? '—' : row.sku,
                        style: AppTypography.productName(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'legacy_id: ${row.legacyId}',
                        style: AppTypography.productMeta(),
                      ),
                      if (row.soldDateKst != null && row.soldDateKst!.isNotEmpty)
                        Text(
                          'KST ${row.soldDateKst}',
                          style: AppTypography.productMeta(),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatWon(row.priceKrw),
                      style: AppTypography.price(fontSize: 15).copyWith(
                        color: row.isReturnLine ? AppColors.saleRed : null,
                      ),
                    ),
                    if (showReturnedBadge) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
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
                            : TextButton.icon(
                                onPressed: onReturn,
                                icon: Icon(
                                  Icons.assignment_return_outlined,
                                  size: 18,
                                  color: AppColors.accent.withValues(alpha: 0.95),
                                ),
                                label: const Text('Возврат товара'),
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
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

class _Thumb extends StatelessWidget {
  const _Thumb({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    const size = 56.0;
    if (url == null || url!.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(
          Icons.image_not_supported_outlined,
          color: AppColors.textSecondary.withValues(alpha: 0.5),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: size,
        height: size,
        child: Image.network(
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
        ),
      ),
    );
  }
}
