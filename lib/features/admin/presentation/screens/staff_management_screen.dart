import 'package:flutter/material.dart';

import '../../../../core/services/database_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/won_format.dart';
import '../../../profile/domain/models/user_profile.dart';
import '../../../../shared/models/seller_item.dart';
import '../../domain/models/seller_payroll_models.dart';

/// Картотека продавцов и расчёт зарплаты (Incheon super-admin).
class StaffManagementScreen extends StatefulWidget {
  StaffManagementScreen({super.key, DatabaseService? database})
      : database = database ?? DatabaseService.create();

  final DatabaseService database;

  @override
  State<StaffManagementScreen> createState() => _StaffManagementScreenState();
}

class _StaffManagementScreenState extends State<StaffManagementScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  List<SellerItem> _sellers = const [];
  bool _loadingSellers = true;
  String? _sellersError;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _reloadSellers();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _reloadSellers() async {
    setState(() {
      _loadingSellers = true;
      _sellersError = null;
    });
    try {
      final list = await widget.database.getSellers(UserRole.admin);
      if (!mounted) return;
      setState(() {
        _sellers = list;
        _loadingSellers = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingSellers = false;
        _sellersError = error.toString();
      });
    }
  }

  Future<void> _openUpsertDialog({SellerItem? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _StaffUpsertDialog(
        database: widget.database,
        existing: existing,
      ),
    );
    if (saved == true && mounted) await _reloadSellers();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Управление персоналом',
              style: AppTypography.heading(fontSize: 22),
            ),
            const SizedBox(height: 12),
            TabBar(
              controller: _tabs,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              tabs: const [
                Tab(text: 'Сотрудники'),
                Tab(text: 'Зарплата и продажи'),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _StaffListTab(
                    loading: _loadingSellers,
                    error: _sellersError,
                    sellers: _sellers,
                    onAdd: () => _openUpsertDialog(),
                    onEdit: (seller) => _openUpsertDialog(existing: seller),
                    onReload: _reloadSellers,
                  ),
                  StaffPayrollTab(database: widget.database),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaffListTab extends StatelessWidget {
  const _StaffListTab({
    required this.loading,
    required this.error,
    required this.sellers,
    required this.onAdd,
    required this.onEdit,
    required this.onReload,
  });

  final bool loading;
  final String? error;
  final List<SellerItem> sellers;
  final VoidCallback onAdd;
  final void Function(SellerItem seller) onEdit;
  final Future<void> Function() onReload;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Код сотрудника (6 символов) — promo_code; ставки комиссии '
                'золото/серебро учитываются в расчёте зарплаты.',
                style: AppTypography.productMeta(),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: loading ? null : onAdd,
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Добавить'),
            ),
            IconButton(
              tooltip: 'Обновить',
              onPressed: loading ? null : onReload,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: loading
              ? const Center(child: CircularProgressIndicator())
              : error != null
                  ? Center(
                      child: Text(
                        'Ошибка загрузки: $error',
                        style: AppTypography.productMeta(),
                      ),
                    )
                  : sellers.isEmpty
                      ? Center(
                          child: Text(
                            'Нет записей. Добавьте первого сотрудника.',
                            style: AppTypography.productMeta(),
                          ),
                        )
                      : Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: const BorderSide(color: AppColors.border),
                          ),
                          child: ListView.separated(
                            itemCount: sellers.length,
                            separatorBuilder: (_, _) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final seller = sellers[index];
                              return ListTile(
                                title: Text(seller.name),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      seller.promoCode,
                                      style: AppTypography.productMeta(),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Золото: ${seller.goldCommissionPercent}% · '
                                      'Серебро: ${seller.silverCommissionPercent}%',
                                      style: AppTypography.productMeta()
                                          .copyWith(fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                                isThreeLine: true,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Chip(
                                      label: Text(
                                        seller.isActive ? 'Активен' : 'Отключён',
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      backgroundColor: seller.isActive
                                          ? Colors.green.withValues(alpha: 0.12)
                                          : AppColors.saleRed
                                              .withValues(alpha: 0.12),
                                    ),
                                    IconButton(
                                      tooltip: 'Редактировать',
                                      onPressed: () => onEdit(seller),
                                      icon: const Icon(Icons.edit_outlined),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}

DateTime _kstNow() => DateTime.now().toUtc().add(const Duration(hours: 9));

DateTime _kstDateOnly(DateTime kst) =>
    DateTime(kst.year, kst.month, kst.day);

({DateTime from, DateTime to}) _kstCurrentMonthRange() {
  final now = _kstDateOnly(_kstNow());
  final from = DateTime(now.year, now.month, 1);
  final to = DateTime(now.year, now.month + 1, 0);
  return (from: from, to: to);
}

({DateTime from, DateTime to}) _kstPreviousMonthRange() {
  final now = _kstDateOnly(_kstNow());
  final firstThis = DateTime(now.year, now.month, 1);
  final lastPrev = firstThis.subtract(const Duration(days: 1));
  final from = DateTime(lastPrev.year, lastPrev.month, 1);
  final to = DateTime(lastPrev.year, lastPrev.month, lastPrev.day);
  return (from: from, to: to);
}

String _formatKstDay(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

class StaffPayrollTab extends StatefulWidget {
  const StaffPayrollTab({super.key, required this.database});

  final DatabaseService database;

  @override
  State<StaffPayrollTab> createState() => _StaffPayrollTabState();
}

class _StaffPayrollTabState extends State<StaffPayrollTab> {
  late DateTime _dateFrom;
  late DateTime _dateTo;
  bool _loading = false;
  String? _error;
  List<SellerPayrollRow> _rows = const [];

  @override
  void initState() {
    super.initState();
    final range = _kstCurrentMonthRange();
    _dateFrom = range.from;
    _dateTo = range.to;
    _loadPayroll();
  }

  Future<void> _loadPayroll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await widget.database.fetchSellerPayrollSummary(
        dateFrom: _dateFrom,
        dateTo: _dateTo,
      );
      if (!mounted) return;
      setState(() {
        _rows = raw.map(SellerPayrollRow.fromMap).toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _applyRange({DateTime? from, DateTime? to}) {
    setState(() {
      if (from != null) _dateFrom = from;
      if (to != null) _dateTo = to;
    });
    _loadPayroll();
  }

  int get _totalRevenueKrw =>
      _rows.fold(0, (sum, row) => sum + row.totalSalesKrw);

  int get _totalCommissionKrw =>
      _rows.fold(0, (sum, row) => sum + row.totalCommissionKrw);

  List<SellerPayrollRow> get _visiblePayrollRows => _rows
      .where(
        (row) =>
            row.isUnassigned ||
            row.totalSalesKrw != 0 ||
            row.totalCommissionKrw != 0 ||
            row.returnsCount > 0,
      )
      .toList(growable: false);

  Future<void> _openDetails(SellerPayrollRow row) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => _SellerSalesDetailSheet(
        database: widget.database,
        row: row,
        dateFrom: _dateFrom,
        dateTo: _dateTo,
      ),
    );
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _dateFrom : _dateTo;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    _applyRange(
      from: isFrom ? picked : null,
      to: isFrom ? null : picked,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilledButton.tonal(
              onPressed: _loading
                  ? null
                  : () {
                      final r = _kstCurrentMonthRange();
                      _applyRange(from: r.from, to: r.to);
                    },
              child: const Text('Текущий месяц'),
            ),
            FilledButton.tonal(
              onPressed: _loading
                  ? null
                  : () {
                      final r = _kstPreviousMonthRange();
                      _applyRange(from: r.from, to: r.to);
                    },
              child: const Text('Прошлый месяц'),
            ),
            OutlinedButton(
              onPressed: _loading ? null : () => _pickDate(isFrom: true),
              child: Text('Дата с: ${_formatKstDay(_dateFrom)}'),
            ),
            OutlinedButton(
              onPressed: _loading ? null : () => _pickDate(isFrom: false),
              child: Text('Дата по: ${_formatKstDay(_dateTo)}'),
            ),
            IconButton(
              onPressed: _loading ? null : _loadPayroll,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          color: AppColors.primary.withValues(alpha: 0.06),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: AppColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Выручка за период', style: AppTypography.productMeta()),
                      Text(
                        formatWon(_totalRevenueKrw),
                        style: AppTypography.heading(fontSize: 20),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Фонд зарплаты', style: AppTypography.productMeta()),
                      Text(
                        formatWon(_totalCommissionKrw),
                        style: AppTypography.heading(fontSize: 20),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text(_error!, style: AppTypography.productMeta()))
                  : _rows.isEmpty
                      ? Center(
                          child: Text(
                            'Нет данных за выбранный период',
                            style: AppTypography.productMeta(),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _visiblePayrollRows.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final row = _visiblePayrollRows[index];
                            return _PayrollSellerCard(
                              row: row,
                              onDetails: () => _openDetails(row),
                            );
                          },
                        ),
        ),
      ],
    );
  }
}

class _PayrollSellerCard extends StatelessWidget {
  const _PayrollSellerCard({
    required this.row,
    required this.onDetails,
  });

  final SellerPayrollRow row;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onDetails,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      row.isUnassigned
                          ? row.sellerName
                          : '${row.sellerName} · ${row.promoCode}',
                      style: AppTypography.heading(fontSize: 16),
                    ),
                  ),
                  TextButton(
                    onPressed: onDetails,
                    child: const Text('Детализация'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _metricLine(
                'Золото',
                '${row.goldSalesCount} шт · ${formatWon(row.goldSalesKrw)} → '
                '${formatWon(row.goldCommissionKrw)}',
              ),
              _metricLine(
                'Серебро',
                '${row.silverSalesCount} шт · ${formatWon(row.silverSalesKrw)} → '
                '${formatWon(row.silverCommissionKrw)}',
              ),
              if (row.returnsCount > 0)
                _metricLine(
                  'Удержания (возвраты)',
                  '${row.returnsCount} шт · ${formatWon(row.returnsCommissionKrw)}',
                  danger: true,
                ),
              const Divider(height: 20),
              Text(
                'Итого к выплате: ${formatWon(row.totalCommissionKrw)}',
                style: AppTypography.price(fontSize: 15),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _metricLine(String title, String value, {bool danger = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(title, style: AppTypography.productMeta()),
          ),
          Expanded(
            child: Text(
              value,
              style: AppTypography.productMeta().copyWith(
                color: danger ? AppColors.saleRed : null,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SellerSalesDetailSheet extends StatefulWidget {
  const _SellerSalesDetailSheet({
    required this.database,
    required this.row,
    required this.dateFrom,
    required this.dateTo,
  });

  final DatabaseService database;
  final SellerPayrollRow row;
  final DateTime dateFrom;
  final DateTime dateTo;

  @override
  State<_SellerSalesDetailSheet> createState() =>
      _SellerSalesDetailSheetState();
}

class _SellerSalesDetailSheetState extends State<_SellerSalesDetailSheet> {
  bool _loading = true;
  String? _error;
  List<SellerSaleDetailRow> _lines = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final code = widget.row.isUnassigned
          ? SellerPayrollRow.unassignedCode
          : widget.row.promoCode;
      final raw = await widget.database.fetchSellerSalesDetails(
        sellerCode: code,
        dateFrom: widget.dateFrom,
        dateTo: widget.dateTo,
      );
      if (!mounted) return;
      setState(() {
        _lines = raw.map(SellerSaleDetailRow.fromMap).toList();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * 0.82;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.row.isUnassigned
                    ? 'Продажи без продавца'
                    : widget.row.sellerName,
                style: AppTypography.heading(fontSize: 18),
              ),
              Text(
                '${_formatKstDay(widget.dateFrom)} — ${_formatKstDay(widget.dateTo)}',
                style: AppTypography.productMeta(),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                        ? Center(child: Text(_error!))
                        : _lines.isEmpty
                            ? Center(
                                child: Text(
                                  'Нет операций',
                                  style: AppTypography.productMeta(),
                                ),
                              )
                            : ListView.separated(
                                itemCount: _lines.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  return _SaleDetailTile(line: _lines[index]);
                                },
                              ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SaleDetailTile extends StatelessWidget {
  const _SaleDetailTile({required this.line});

  final SellerSaleDetailRow line;

  @override
  Widget build(BuildContext context) {
    final accent = line.isReturn ? AppColors.saleRed : AppColors.textPrimary;
    final url = line.imageUrl;
    final dateLabel = line.soldAt != null
        ? '${line.soldAt!.toLocal()}'.substring(0, 16)
        : '—';

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 6),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 56,
          height: 56,
          child: url != null && url.isNotEmpty
              ? Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const _PhotoPlaceholder(),
                )
              : const _PhotoPlaceholder(),
        ),
      ),
      title: Text(
        line.sku,
        style: AppTypography.caption(fontWeight: FontWeight.w700),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(line.productName, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(
            '$dateLabel · ${line.metalLabel.isNotEmpty ? line.metalLabel : line.metalCategory}',
            style: AppTypography.productMeta(),
          ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            formatWon(line.priceKrw),
            style: AppTypography.price(fontSize: 13, color: accent),
          ),
          Text(
            '${line.commissionKrw >= 0 ? '+' : ''}${formatWon(line.commissionKrw)} '
            '(${line.commissionPercent}%)',
            style: AppTypography.productMeta().copyWith(
              color: accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
      child: const Icon(Icons.image_not_supported_outlined, size: 22),
    );
  }
}

class _StaffUpsertDialog extends StatefulWidget {
  const _StaffUpsertDialog({
    required this.database,
    this.existing,
  });

  final DatabaseService database;
  final SellerItem? existing;

  bool get isEdit => existing != null;

  @override
  State<_StaffUpsertDialog> createState() => _StaffUpsertDialogState();
}

class _StaffUpsertDialogState extends State<_StaffUpsertDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _codeController;
  late final TextEditingController _goldPercentController;
  late final TextEditingController _silverPercentController;
  late bool _isActive;
  bool _saving = false;
  String? _error;

  static final _codePattern = RegExp(r'^[A-Z0-9]{6}$');

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _codeController = TextEditingController(text: existing?.promoCode ?? '');
    _goldPercentController = TextEditingController(
      text: existing != null ? '${existing.goldCommissionPercent}' : '0',
    );
    _silverPercentController = TextEditingController(
      text: existing != null ? '${existing.silverCommissionPercent}' : '0',
    );
    _isActive = existing?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _goldPercentController.dispose();
    _silverPercentController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final code = SellerItem.normalizePromoCode(_codeController.text);
  final gold = SellerItem.parseCommissionPercentInput(_goldPercentController.text);
  final silver =
      SellerItem.parseCommissionPercentInput(_silverPercentController.text);
    if (name.isEmpty) {
      setState(() => _error = 'Укажите имя');
      return;
    }
    if (!_codePattern.hasMatch(code)) {
      setState(
        () => _error = 'Код: ровно 6 латинских букв или цифр (A–Z, 0–9)',
      );
      return;
    }
    if (gold == null || silver == null) {
      setState(() => _error = 'Некорректный процент комиссии');
      return;
    }
    if (gold < 0 || gold > 100 || silver < 0 || silver > 100) {
      setState(() => _error = 'Процент комиссии: от 0 до 100');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.database.upsertSellerByAdmin(
        promoCode: code,
        name: name,
        isActive: _isActive,
        goldCommissionPercent: gold,
        silverCommissionPercent: silver,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      final message = error is StateError
          ? error.message
          : error.toString().replaceFirst('Exception: ', '');
      setState(() {
        _saving = false;
        _error = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.isEdit ? 'Редактировать сотрудника' : 'Добавить сотрудника',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Имя',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _codeController,
              enabled: !widget.isEdit,
              decoration: const InputDecoration(
                labelText: 'Код сотрудника (6 символов)',
                border: OutlineInputBorder(),
                helperText: 'Например: AEU256',
              ),
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _goldPercentController,
              decoration: const InputDecoration(
                labelText: 'Процент за золото (%)',
                border: OutlineInputBorder(),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _silverPercentController,
              decoration: const InputDecoration(
                labelText: 'Процент за серебро (%)',
                border: OutlineInputBorder(),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Активен'),
              value: _isActive,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _isActive = value),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
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
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Сохранить'),
        ),
      ],
    );
  }
}