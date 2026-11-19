import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/services/database_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/won_format.dart';
import '../../../admin/domain/models/seller_payroll_models.dart';

DateTime _kstNow() => DateTime.now().toUtc().add(const Duration(hours: 9));

DateTime _kstDateOnly(DateTime kst) =>
    DateTime(kst.year, kst.month, kst.day);

({DateTime from, DateTime to}) kstMonthRange(int year, int month) {
  final from = DateTime(year, month, 1);
  final to = DateTime(year, month + 1, 0);
  return (from: from, to: to);
}

({DateTime from, DateTime to}) kstCurrentMonthRange() {
  final now = _kstDateOnly(_kstNow());
  return kstMonthRange(now.year, now.month);
}

String formatKstDay(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

String kstMonthTitle(int year, int month) {
  final anchor = DateTime(year, month, 1);
  final label = DateFormat('LLLL y', 'ru').format(anchor);
  if (label.isEmpty) return '$month.$year';
  return '${label[0].toUpperCase()}${label.substring(1)}';
}

/// Личный кабинет продавца: зарплата и операции за выбранный месяц (KST).
class SellerMyPayrollScreen extends StatefulWidget {
  const SellerMyPayrollScreen({
    super.key,
    required this.promoCode,
    required this.sellerName,
    this.database,
  });

  final String promoCode;
  final String sellerName;
  final DatabaseService? database;

  @override
  State<SellerMyPayrollScreen> createState() => _SellerMyPayrollScreenState();
}

class _SellerMyPayrollScreenState extends State<SellerMyPayrollScreen> {
  late final DatabaseService _database;
  late int _monthYear;
  late int _month;

  bool _loading = true;
  String? _error;
  SellerPayrollRow? _summary;
  List<SellerSaleDetailRow> _lines = const [];

  DateTime get _dateFrom => kstMonthRange(_monthYear, _month).from;
  DateTime get _dateTo => kstMonthRange(_monthYear, _month).to;

  @override
  void initState() {
    super.initState();
    _database = widget.database ?? DatabaseService.create();
    final current = kstCurrentMonthRange();
    _monthYear = current.from.year;
    _month = current.from.month;
    _load();
  }

  List<({int year, int month, String label})> get _monthOptions {
    final now = _kstDateOnly(_kstNow());
    final options = <({int year, int month, String label})>[];
    for (var i = 0; i < 12; i++) {
      final anchor = DateTime(now.year, now.month - i, 1);
      options.add((
        year: anchor.year,
        month: anchor.month,
        label: kstMonthTitle(anchor.year, anchor.month),
      ));
    }
    return options;
  }

  void _shiftMonth(int delta) {
    final anchor = DateTime(_monthYear, _month + delta, 1);
    setState(() {
      _monthYear = anchor.year;
      _month = anchor.month;
    });
    _load();
  }

  void _pickMonth(({int year, int month, String label}) option) {
    setState(() {
      _monthYear = option.year;
      _month = option.month;
    });
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final summaryRaw = await _database.fetchMySellerPayrollSummary(
        promoCode: widget.promoCode,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
      );
      final detailsRaw = await _database.fetchMySellerSalesDetails(
        promoCode: widget.promoCode,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
      );
      if (!mounted) return;
      setState(() {
        _summary = summaryRaw != null
            ? SellerPayrollRow.fromMap(summaryRaw)
            : null;
        _lines = detailsRaw.map(SellerSaleDetailRow.fromMap).toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    final monthLabel = kstMonthTitle(_monthYear, _month);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              '${widget.sellerName} · ${widget.promoCode}',
              style: AppTypography.heading(fontSize: 20),
            ),
            const SizedBox(height: 4),
            Text(
              'Моя зарплата и продажи',
              style: AppTypography.productMeta(),
            ),
            const SizedBox(height: 16),
            _MonthPickerBar(
              monthLabel: monthLabel,
              onPrev: () => _shiftMonth(-1),
              onNext: () => _shiftMonth(1),
              options: _monthOptions,
              selectedYear: _monthYear,
              selectedMonth: _month,
              onPick: _pickMonth,
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Text(_error!, style: AppTypography.productMeta())
            else if (summary == null)
              Text(
                'Нет данных за период',
                style: AppTypography.productMeta(),
              )
            else ...[
              _PayrollSummaryCard(row: summary, monthLabel: monthLabel),
              const SizedBox(height: 20),
              Text(
                'Операции за месяц',
                style: AppTypography.heading(fontSize: 16),
              ),
              const SizedBox(height: 8),
              if (_lines.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Нет продаж и возвратов',
                    style: AppTypography.productMeta(),
                  ),
                )
              else
                ..._lines.map((line) => _SaleOperationCard(line: line)),
            ],
          ],
        ),
      ),
    );
  }
}

class _MonthPickerBar extends StatelessWidget {
  const _MonthPickerBar({
    required this.monthLabel,
    required this.onPrev,
    required this.onNext,
    required this.options,
    required this.selectedYear,
    required this.selectedMonth,
    required this.onPick,
  });

  final String monthLabel;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final List<({int year, int month, String label})> options;
  final int selectedYear;
  final int selectedMonth;
  final void Function(({int year, int month, String label}) option) onPick;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Предыдущий месяц',
              onPressed: onPrev,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: DropdownButtonHideUnderline(
                child: DropdownButton<({int year, int month, String label})>(
                  isExpanded: true,
                  value: options.firstWhere(
                    (o) => o.year == selectedYear && o.month == selectedMonth,
                    orElse: () => options.first,
                  ),
                  items: [
                    for (final option in options)
                      DropdownMenuItem(
                        value: option,
                        child: Text(option.label),
                      ),
                  ],
                  onChanged: (value) {
                    if (value != null) onPick(value);
                  },
                ),
              ),
            ),
            IconButton(
              tooltip: 'Следующий месяц',
              onPressed: onNext,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }
}

class _PayrollSummaryCard extends StatelessWidget {
  const _PayrollSummaryCard({
    required this.row,
    required this.monthLabel,
  });

  final SellerPayrollRow row;
  final String monthLabel;

  @override
  Widget build(BuildContext context) {
    final hasReturns = row.returnsCount > 0;
    final returnAccent = AppColors.saleRed;

    return Card(
      elevation: 0,
      color: AppColors.primary.withValues(alpha: 0.06),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('К выплате · $monthLabel', style: AppTypography.productMeta()),
            Text(
              formatWon(row.totalCommissionKrw),
              style: AppTypography.heading(fontSize: 28),
            ),
            const SizedBox(height: 16),
            _MetricRow(
              title: 'Золото',
              count: row.goldSalesCount,
              salesKrw: row.goldSalesKrw,
              commissionKrw: row.goldCommissionKrw,
              rate: row.goldCommissionPercent,
            ),
            const SizedBox(height: 10),
            _MetricRow(
              title: 'Серебро',
              count: row.silverSalesCount,
              salesKrw: row.silverSalesKrw,
              commissionKrw: row.silverCommissionKrw,
              rate: row.silverCommissionPercent,
            ),
            const Divider(height: 24),
            Text(
              'Вычеты за возвраты в этом месяце',
              style: AppTypography.caption(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              hasReturns
                  ? '${row.returnsCount} шт. · комиссия ${formatWon(row.returnsCommissionKrw)}'
                  : 'Возвратов нет · ${formatWon(0)}',
              style: AppTypography.productMeta().copyWith(
                color: hasReturns ? returnAccent : null,
                fontWeight: hasReturns ? FontWeight.w700 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.title,
    required this.count,
    required this.salesKrw,
    required this.commissionKrw,
    required this.rate,
  });

  final String title;
  final int count;
  final int salesKrw;
  final int commissionKrw;
  final double rate;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 2,
          child: Text(
            title,
            style: AppTypography.caption(fontWeight: FontWeight.w700),
          ),
        ),
        Expanded(
          flex: 5,
          child: Text(
            '$count шт. · продажи ${formatWon(salesKrw)}',
            style: AppTypography.productMeta(),
          ),
        ),
        Expanded(
          flex: 3,
          child: Text(
            '+${formatWon(commissionKrw)} (${rate.toStringAsFixed(1)}%)',
            style: AppTypography.productMeta().copyWith(
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}

class _SaleOperationCard extends StatelessWidget {
  const _SaleOperationCard({required this.line});

  final SellerSaleDetailRow line;

  @override
  Widget build(BuildContext context) {
    final isReturn = line.isReturn;
    final accent = isReturn ? AppColors.saleRed : AppColors.textPrimary;
    final commissionPrefix = line.commissionKrw >= 0 ? '+' : '';
    final dateLabel = line.soldDateKst ??
        (line.soldAt != null
            ? formatKstDay(
                line.soldAt!.toUtc().add(const Duration(hours: 9)),
              )
            : '—');
    final url = line.imageUrl;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isReturn
              ? AppColors.saleRed.withValues(alpha: 0.35)
              : AppColors.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 72,
                height: 72,
                child: url != null && url.isNotEmpty
                    ? Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const _PhotoPlaceholder(),
                      )
                    : const _PhotoPlaceholder(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          line.sku,
                          style: AppTypography.caption(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (isReturn)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.saleRed.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Возврат',
                            style: AppTypography.productMeta().copyWith(
                              color: AppColors.saleRed,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    line.productName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.productMeta(),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'KST $dateLabel'
                    '${line.weightGrams != null && line.weightGrams! > 0 ? ' · ${line.weightGrams!.toStringAsFixed(2)} г' : ''}'
                    '${line.metalLabel.isNotEmpty ? ' · ${line.metalLabel}' : ''}',
                    style: AppTypography.productMeta(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    formatWon(line.priceKrw),
                    style: AppTypography.price(fontSize: 15, color: accent),
                  ),
                  Text(
                    '$commissionPrefix${formatWon(line.commissionKrw)} '
                    '(${line.commissionPercent}%)',
                    style: AppTypography.productMeta().copyWith(
                      color: accent,
                      fontWeight: FontWeight.w600,
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

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.border.withValues(alpha: 0.35),
      child: const Icon(Icons.image_not_supported_outlined, size: 28),
    );
  }
}