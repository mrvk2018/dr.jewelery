import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../core/utils/won_format.dart';
import '../models/sales_history_row.dart';
import '../services/sales_history_service.dart';

String kstTodayIsoDate() {
  final kst = DateTime.now().toUtc().add(const Duration(hours: 9));
  final y = kst.year.toString().padLeft(4, '0');
  final m = kst.month.toString().padLeft(2, '0');
  final d = kst.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

class SalesHistoryScreen extends StatefulWidget {
  const SalesHistoryScreen({super.key, this.repository});

  final SalesHistoryRepository? repository;

  @override
  State<SalesHistoryScreen> createState() => _SalesHistoryScreenState();
}

class _SalesHistoryScreenState extends State<SalesHistoryScreen> {
  late final SalesHistoryRepository _repo;
  final _scrollController = ScrollController();
  final _rows = <SalesHistoryRow>[];

  String _selectedDateKst = kstTodayIsoDate();
  int? _dayRevenueKrw;
  bool _kpiLoading = false;
  bool _listLoading = false;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _pageIndex = 0;
  String? _error;
  String? _returnBusySku;

  @override
  void initState() {
    super.initState();
    _repo = widget.repository ?? SalesHistoryRepository();
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

  Future<void> _loadInitial() async {
    setState(() {
      _listLoading = true;
      _kpiLoading = true;
      _error = null;
      _rows.clear();
      _pageIndex = 0;
      _hasMore = true;
    });

    try {
      final revenue = await _repo.sumPriceKrwForSoldDateKst(_selectedDateKst);
      final page = await _repo.fetchPage(
        pageIndex: 0,
        soldDateKst: _selectedDateKst,
      );
      if (!mounted) return;
      setState(() {
        _dayRevenueKrw = revenue;
        _rows.addAll(page);
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
        soldDateKst: _selectedDateKst,
      );
      if (!mounted) return;
      setState(() {
        _rows.addAll(page);
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

  Future<void> _pickDate() async {
    final initial = DateTime.tryParse(_selectedDateKst) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: 'День продажи (KST)',
    );
    if (picked == null || !mounted) return;
    final iso =
        '${picked.year.toString().padLeft(4, '0')}-'
        '${picked.month.toString().padLeft(2, '0')}-'
        '${picked.day.toString().padLeft(2, '0')}';
    setState(() => _selectedDateKst = iso);
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

  Future<void> _confirmReturn(SalesHistoryRow row) async {
    if (row.sku.isEmpty || row.isReturnLine) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Возврат на витрину', style: AppTypography.heading(fontSize: 18)),
        content: Text(
          'Вы уверены, что хотите оформить возврат товара ${row.sku} на витрину? '
          'Финансовые показатели будут скорректированы.',
          style: AppTypography.productMeta(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Возврат'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _returnBusySku = row.sku);
    try {
      final reversal = await _repo.processProductReturn(row.sku);
      if (!mounted) return;
      setState(() {
        final idx = _rows.indexWhere(
          (r) => r.legacyId == row.legacyId || r.id == row.id,
        );
        if (idx >= 0) {
          _rows.insert(idx + 1, reversal);
        } else {
          _rows.insert(0, reversal);
        }
        if (_dayRevenueKrw != null) {
          _dayRevenueKrw = _dayRevenueKrw! + reversal.priceKrw;
        }
        _returnBusySku = null;
      });
      _snack('Товар ${row.sku} возвращён на витрину');
    } catch (error) {
      if (!mounted) return;
      setState(() => _returnBusySku = null);
      _snack(error.toString(), error: true);
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
            selectedDateKst: _selectedDateKst,
            revenueKrw: _dayRevenueKrw,
            loading: _kpiLoading,
            onPickDate: _pickDate,
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
                          returnBusy: _returnBusySku == row.sku,
                          onTap: () => _showPayloadDialog(row),
                          onReturn: row.isReturnLine
                              ? null
                              : () => _confirmReturn(row),
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
    required this.selectedDateKst,
    required this.revenueKrw,
    required this.loading,
    required this.onPickDate,
  });

  final String selectedDateKst;
  final int? revenueKrw;
  final bool loading;
  final VoidCallback onPickDate;

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
                  'Выручка за день (KST)',
                  style: AppTypography.caption(
                    color: AppColors.textOnPrimary,
                    fontWeight: FontWeight.w600,
                  ).copyWith(fontSize: 14),
                ),
              ),
              OutlinedButton.icon(
                onPressed: onPickDate,
                icon: const Icon(Icons.calendar_month_outlined, size: 18),
                label: Text(selectedDateKst),
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
            'Сумма price_krw по sold_date_kst',
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
  });

  final SalesHistoryRow row;
  final VoidCallback onTap;
  final VoidCallback? onReturn;
  final bool returnBusy;

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
                                label: const Text('Возврат'),
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
