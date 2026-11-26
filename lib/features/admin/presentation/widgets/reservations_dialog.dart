import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/services/database_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/krw_text.dart';
import '../../domain/models/reservation_record.dart';
import 'reservation_ui.dart';

class ReservationsDialog extends StatefulWidget {
  const ReservationsDialog({
    super.key,
    required this.database,
    this.sellerName,
    this.sellerCode,
    this.lockSeller = false,
  });

  final DatabaseService database;
  final String? sellerName;
  final String? sellerCode;
  final bool lockSeller;

  @override
  State<ReservationsDialog> createState() => _ReservationsDialogState();
}

class _ReservationsDialogState extends State<ReservationsDialog> {
  static const _filters = <(String, String)>[
    ('active', 'Активные'),
    ('expired', 'Просроченные'),
    ('completed', 'Выкупленные'),
    ('cancelled', 'Отменённые'),
    ('all', 'Все'),
  ];

  String _filter = 'active';
  String _branch = 'ALL';
  var _loading = true;
  var _changed = false;
  String? _error;
  List<ReservationRecord> _rows = const [];
  Timer? _searchDebounce;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await widget.database.listReservations(
      filter: _filter,
      search: _searchController.text,
      branch: _branch,
    );
    if (!mounted) return;
    if (result['ok'] == true) {
      setState(() {
        _rows = ReservationRecord.listFromRpc(result);
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = false;
      _error = reservationErrorMessage(result['error']);
    });
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _pay(ReservationRecord reservation) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (context) => _PayReservationDialog(
        database: widget.database,
        reservation: reservation,
        sellerName: _sellerName(reservation),
        sellerCode: _sellerCode(reservation),
      ),
    );
    if (done == true) {
      _changed = true;
      await _load();
    }
  }

  Future<void> _cancel(ReservationRecord reservation) async {
    final done = await showDialog<bool>(
      context: context,
      builder: (context) => _CancelReservationDialog(
        database: widget.database,
        reservation: reservation,
        sellerName: _sellerName(reservation),
        sellerCode: _sellerCode(reservation),
      ),
    );
    if (done == true) {
      _changed = true;
      await _load();
    }
  }

  String _sellerName(ReservationRecord reservation) {
    if (widget.lockSeller) {
      final name = widget.sellerName?.trim();
      if (name != null && name.isNotEmpty) return name;
    }
    return reservation.sellerName ?? widget.sellerName ?? '';
  }

  String? _sellerCode(ReservationRecord reservation) {
    if (widget.lockSeller) {
      final code = widget.sellerCode?.trim();
      if (code != null && code.isNotEmpty) return code;
    }
    return reservation.sellerCode ?? widget.sellerCode;
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 920, maxHeight: height * 0.94),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Брони и залоги',
                      style: AppTypography.heading(fontSize: 18),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(_changed),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final filter in _filters)
                        ChoiceChip(
                          label: Text(filter.$2),
                          selected: _filter == filter.$1,
                          onSelected: (_) {
                            setState(() => _filter = filter.$1);
                            _load();
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 280,
                        child: TextField(
                          controller: _searchController,
                          onChanged: _onSearchChanged,
                          decoration: const InputDecoration(
                            isDense: true,
                            prefixIcon: Icon(Icons.search),
                            hintText: 'Имя, телефон или артикул',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      DropdownButton<String>(
                        value: _branch,
                        items: const [
                          DropdownMenuItem(value: 'ALL', child: Text('Все филиалы')),
                          DropdownMenuItem(value: 'ICN', child: Text('Инчхон (ICN)')),
                          DropdownMenuItem(value: 'ANS', child: Text('Ансан (ANS)')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _branch = value);
                          _load();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Text(_error!, style: TextStyle(color: AppColors.saleRed)),
      );
    }
    if (_rows.isEmpty) {
      return const Center(child: Text('Броней нет'));
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: _rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final row = _rows[index];
        return _ReservationCard(
          reservation: row,
          onPay: row.canAct ? () => _pay(row) : null,
          onCancel: row.canAct ? () => _cancel(row) : null,
        );
      },
    );
  }
}

class _ReservationCard extends StatelessWidget {
  const _ReservationCard({
    required this.reservation,
    required this.onPay,
    required this.onCancel,
  });

  final ReservationRecord reservation;
  final VoidCallback? onPay;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final meta = AppTypography.productMeta();
    final expired = reservation.isExpired || reservation.displayStatus == 'expired';
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: expired ? AppColors.saleRed : AppColors.border,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  reservation.customerName,
                  style: AppTypography.productTitle.copyWith(fontSize: 16),
                ),
                Text(reservation.customerPhone, style: meta),
                if (expired)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.saleRed,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      'Просрочена',
                      style: meta.copyWith(color: AppColors.textOnPrimary, fontSize: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Оформлена: ${formatReservationWhen(reservation.createdAt)}'
              ' · до ${formatReservationWhen(reservation.expiresAt)}',
              style: meta,
            ),
            Text(
              '${reservationBranchLabel(reservation.branch)}'
              '${reservation.sellerName == null ? '' : ' · ${reservation.sellerName}'}',
              style: meta,
            ),
            if (reservation.receiptNumber != null)
              Text('Квитанция ${reservation.receiptNumber}', style: meta),
            if (reservation.comment != null)
              Text(reservation.comment!, style: meta),
            const SizedBox(height: 8),
            for (final item in reservation.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        [
                          item.sku,
                          if (item.title != null && item.title != item.sku) item.title!,
                          if (item.specs.isNotEmpty) item.specs,
                        ].join(' · '),
                        style: meta,
                      ),
                    ),
                    KrwText(
                      amount: item.agreedPriceKrw,
                      style: meta,
                      digitStyle: meta,
                    ),
                  ],
                ),
              ),
            const Divider(height: 16),
            ReservationMoneyRow(
              label: 'Общая сумма',
              amount: reservation.totalAmountKrw,
            ),
            ReservationMoneyRow(
              label: 'Внесено залога',
              amount: reservation.paidDepositKrw,
            ),
            ReservationMoneyRow(
              label: 'Остаток к доплате',
              amount: reservation.balanceKrw,
              emphasize: true,
            ),
            if (reservation.payments.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(
                  'Платежи (${reservation.payments.length})',
                  style: meta.copyWith(fontWeight: FontWeight.w600),
                ),
                children: [
                  for (final payment in reservation.payments)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${reservationPaymentTypeLabel(payment.paymentType)}'
                              ' · ${reservationPaymentLabel(payment.paymentMethod)}'
                              ' · ${formatReservationWhen(payment.createdAt)}',
                              style: meta,
                            ),
                          ),
                          KrwText(
                            amount: payment.amountKrw,
                            style: meta,
                            digitStyle: meta,
                            showPlusSign: payment.amountKrw > 0,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            if (onPay != null || onCancel != null) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (onPay != null)
                    FilledButton(
                      onPressed: onPay,
                      child: const Text('Доплатить / Выкупить'),
                    ),
                  if (onCancel != null)
                    OutlinedButton(
                      onPressed: onCancel,
                      child: const Text('Отменить бронь'),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PayReservationDialog extends StatefulWidget {
  const _PayReservationDialog({
    required this.database,
    required this.reservation,
    required this.sellerName,
    required this.sellerCode,
  });

  final DatabaseService database;
  final ReservationRecord reservation;
  final String sellerName;
  final String? sellerCode;

  @override
  State<_PayReservationDialog> createState() => _PayReservationDialogState();
}

class _PayReservationDialogState extends State<_PayReservationDialog> {
  late String _method;
  late String _branch;
  late bool _full;
  late int _amount;
  var _busy = false;
  String? _error;

  int get _due => widget.reservation.balanceKrw;

  @override
  void initState() {
    super.initState();
    _method = reservationPaymentMethods.first;
    _branch = widget.reservation.branch;
    _full = true;
    _amount = _due;
  }

  Future<void> _submit() async {
    final amount = _full ? _due : _amount;
    if (amount <= 0 || amount > _due) {
      setState(() => _error = reservationErrorMessage('invalid_amount'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.database.payReservationBalance(
      reservationId: widget.reservation.id,
      paymentAmountKrw: amount,
      paymentMethod: _method,
      branch: _branch,
      sellerName: widget.sellerName,
      sellerCode: widget.sellerCode,
    );
    if (!mounted) return;
    if (result['ok'] == true) {
      final completed = result['completed'] == true;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            completed
                ? 'Бронь выкуплена. Продажа проведена в «Историю продаж».'
                : 'Доплата принята. Остаток обновлён.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _busy = false;
      _error = reservationErrorMessage(result['error']);
    });
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 480, maxHeight: height * 0.9),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'Доплатить / Выкупить',
                style: AppTypography.heading(fontSize: 18),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ReservationMoneyRow(
                      label: 'Общая сумма',
                      amount: widget.reservation.totalAmountKrw,
                    ),
                    ReservationMoneyRow(
                      label: 'Внесено залога',
                      amount: widget.reservation.paidDepositKrw,
                    ),
                    ReservationMoneyRow(
                      label: 'Остаток к доплате',
                      amount: _due,
                      emphasize: true,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: const Text('Выкупить полностью (весь остаток)'),
                          selected: _full,
                          onSelected: _busy
                              ? null
                              : (_) => setState(() {
                                    _full = true;
                                    _amount = _due;
                                  }),
                        ),
                        ChoiceChip(
                          label: const Text('Частичная доплата'),
                          selected: !_full,
                          onSelected: _busy
                              ? null
                              : (_) => setState(() => _full = false),
                        ),
                      ],
                    ),
                    if (!_full) ...[
                      const SizedBox(height: 12),
                      ReservationAmountField(
                        amount: _amount,
                        enabled: !_busy,
                        label: 'Сумма доплаты, ₩',
                        onChanged: (value) => setState(() => _amount = value),
                      ),
                    ],
                    const SizedBox(height: 12),
                    ReservationPaymentPicker(
                      value: _method,
                      enabled: !_busy,
                      onChanged: (value) => setState(() => _method = value),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _branch == 'ANS' ? 'ANS' : 'ICN',
                      decoration: const InputDecoration(
                        labelText: 'Филиал кассы',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'ICN', child: Text('Инчхон (ICN)')),
                        DropdownMenuItem(value: 'ANS', child: Text('Ансан (ANS)')),
                      ],
                      onChanged: _busy
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() => _branch = value);
                            },
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: TextStyle(color: AppColors.saleRed)),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => Navigator.of(context).pop(),
                      child: const Text('Отмена'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Text(_full ? 'Выкупить полностью' : 'Принять доплату'),
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

class _CancelReservationDialog extends StatefulWidget {
  const _CancelReservationDialog({
    required this.database,
    required this.reservation,
    required this.sellerName,
    required this.sellerCode,
  });

  final DatabaseService database;
  final ReservationRecord reservation;
  final String sellerName;
  final String? sellerCode;

  @override
  State<_CancelReservationDialog> createState() =>
      _CancelReservationDialogState();
}

class _CancelReservationDialogState extends State<_CancelReservationDialog> {
  var _refund = false;
  var _busy = false;
  String _method = reservationPaymentMethods.first;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.database.cancelReservation(
      reservationId: widget.reservation.id,
      refundDeposit: _refund,
      refundMethod: _refund ? _method : null,
      branch: widget.reservation.branch,
      sellerName: widget.sellerName,
      sellerCode: widget.sellerCode,
    );
    if (!mounted) return;
    if (result['ok'] == true) {
      final kept = !_refund;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            kept
                ? 'Бронь отменена. Изделия снова на витрине, залог остался в доходе.'
                : 'Бронь отменена. Залог списан из кассы, изделия снова на витрине.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _busy = false;
      _error = reservationErrorMessage(result['error']);
    });
  }

  @override
  Widget build(BuildContext context) {
    final meta = AppTypography.productMeta();
    return AlertDialog(
      title: const Text('Отменить бронь'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Изделия вернутся в продажу на витрину.',
              style: meta,
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _refund,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _refund = value ?? false),
              title: const Text('Вернуть залог клиенту'),
              subtitle: Text(
                _refund
                    ? 'Сумма залога будет списана из кассы смены выбранным способом.'
                    : 'Залог не возвращается и остаётся в доходе магазина.',
                style: meta,
              ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (_refund) ...[
              const SizedBox(height: 8),
              ReservationMoneyRow(
                label: 'К возврату',
                amount: widget.reservation.paidDepositKrw,
                emphasize: true,
              ),
              const SizedBox(height: 8),
              ReservationPaymentPicker(
                value: _method,
                enabled: !_busy,
                onChanged: (value) => setState(() => _method = value),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: AppColors.saleRed)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Назад'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: const Text('Отменить бронь'),
        ),
      ],
    );
  }
}
