import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/won_format.dart';
import '../../../../core/widgets/krw_text.dart';

const reservationPaymentMethods = <String>['cash', 'card', 'transfer'];

String reservationPaymentLabel(String value) => switch (value) {
      'cash' => 'Наличные',
      'card' => 'Карта',
      'transfer' => 'Перевод',
      _ => value,
    };

String reservationPaymentTypeLabel(String value) => switch (value) {
      'deposit' => 'Залог',
      'topup' => 'Доплата',
      'buyout' => 'Выкуп',
      'refund' => 'Возврат залога',
      _ => value,
    };

String reservationBranchLabel(String code) => switch (code.toUpperCase()) {
      'ICN' => 'Инчхон (ICN)',
      'ANS' => 'Ансан (ANS)',
      _ => code,
    };

String reservationErrorMessage(Object? raw) {
  final text = raw?.toString() ?? '';
  final lower = text.toLowerCase();
  if (lower.contains('product_unavailable') || lower.contains('reserved')) {
    return 'Изделие уже недоступно: его продали, забронировали или отправили в трансфер.';
  }
  return switch (text) {
    'empty_lines' => 'В корзине нет изделий.',
    'too_many_lines' => 'Слишком много изделий в одной брони.',
    'invalid_line' => 'Проверьте согласованные цены изделий.',
    'duplicate_product' => 'Одно изделие указано дважды.',
    'lines_total_mismatch' => 'Сумма строк не сходится с итогом заказа.',
    'invalid_deposit' => 'Залог должен быть больше 0 и не больше суммы заказа.',
    'invalid_payment_method' => 'Выберите способ оплаты: наличные, карта или перевод.',
    'invalid_branch' => 'Укажите филиал ICN или ANS.',
    'customer_required' => 'Укажите имя и телефон клиента.',
    'invalid_expires_at' => 'Срок брони должен быть позже текущего времени.',
    'seller_not_resolved' => 'Продавец не найден. Выберите продавца из списка.',
    'product_not_found' => 'Изделие не найдено.',
    'reservation_not_found' => 'Бронь не найдена.',
    'reservation_not_active' => 'Бронь уже закрыта.',
    'invalid_amount' => 'Сумма доплаты больше остатка.',
    'invalid_filter' => 'Неизвестный фильтр списка.',
    'invalid_range' => 'Проверьте даты кассы.',
    _ => text.isEmpty ? 'Операция не выполнена.' : text,
  };
}

String formatReservationWhen(DateTime? value) {
  if (value == null) return '—';
  return DateFormat('dd.MM.yyyy HH:mm').format(value);
}

class ReservationMoneyRow extends StatelessWidget {
  const ReservationMoneyRow({
    super.key,
    required this.label,
    required this.amount,
    this.emphasize = false,
  });

  final String label;
  final int amount;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final style = emphasize
        ? AppTypography.productTitle.copyWith(fontWeight: FontWeight.w700)
        : AppTypography.productMeta();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          KrwText(amount: amount, style: style, digitStyle: style),
        ],
      ),
    );
  }
}

class ReservationPaymentPicker extends StatelessWidget {
  const ReservationPaymentPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final String value;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final method in reservationPaymentMethods)
          ChoiceChip(
            label: Text(reservationPaymentLabel(method)),
            selected: value == method,
            onSelected: !enabled
                ? null
                : (_) => onChanged(method),
          ),
      ],
    );
  }
}

/// Сумма в вонах с разделителями тысяч.
int parseKrwAmountInput(String raw) {
  final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
  if (digits.isEmpty) return 0;
  return int.tryParse(digits) ?? 0;
}

class ReservationAmountField extends StatefulWidget {
  const ReservationAmountField({
    super.key,
    required this.amount,
    required this.onChanged,
    this.label = 'Сумма, ₩',
    this.enabled = true,
    this.onEditingStarted,
    this.errorText,
  });

  final int amount;
  final ValueChanged<int> onChanged;
  final String label;
  final bool enabled;
  final VoidCallback? onEditingStarted;
  final String? errorText;

  @override
  State<ReservationAmountField> createState() => _ReservationAmountFieldState();
}

class _ReservationAmountFieldState extends State<ReservationAmountField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _textForAmount(widget.amount));
    _focusNode = FocusNode()..addListener(_onFocusChange);
  }

  String _textForAmount(int amount) =>
      amount > 0 ? formatKrwDigits(amount) : '';

  @override
  void didUpdateWidget(ReservationAmountField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.amount != widget.amount && !_focusNode.hasFocus) {
      _controller.text = _textForAmount(widget.amount);
    }
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      final synced = _textForAmount(widget.amount);
      if (_controller.text != synced) {
        _controller.text = synced;
      }
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _notifyEditingStarted() => widget.onEditingStarted?.call();

  void _onChanged(String raw) {
    _notifyEditingStarted();
    final amount = parseKrwAmountInput(raw);
    final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
    final formatted = digits.isEmpty ? '' : formatKrwDigits(amount);
    if (_controller.text != formatted) {
      _controller.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }
    widget.onChanged(amount);
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      readOnly: false,
      enabled: widget.enabled,
      keyboardType: TextInputType.number,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9,\s]')),
      ],
      decoration: InputDecoration(
        labelText: widget.label,
        border: const OutlineInputBorder(),
        errorText: widget.errorText,
      ),
      onTap: _notifyEditingStarted,
      onChanged: _onChanged,
    );
  }
}

DateTime reservationEndOfDay(DateTime day) {
  return DateTime(day.year, day.month, day.day, 23, 59);
}

DateTime reservationPresetExpiry(int days) {
  final base = DateTime.now().add(Duration(days: days));
  return reservationEndOfDay(base);
}
