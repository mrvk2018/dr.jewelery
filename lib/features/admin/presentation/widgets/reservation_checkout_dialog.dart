import 'package:flutter/material.dart';

import '../../../../core/services/database_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/krw_text.dart';
import '../../../../shared/models/product_item.dart';
import '../../domain/models/pos_cart_item.dart';
import 'reservation_ui.dart';

class ReservationCartLine {
  const ReservationCartLine({
    required this.productId,
    required this.sku,
    required this.title,
    required this.specs,
    required this.agreedPriceKrw,
    this.imageUrl,
  });

  final String productId;
  final String sku;
  final String title;
  final String specs;
  final int agreedPriceKrw;
  final String? imageUrl;

  static ReservationCartLine fromCartItem(PosCartItem line) {
    final product = line.product;
    return ReservationCartLine(
      productId: product.id,
      sku: product.sku,
      title: product.localizedName('ru'),
      specs: _specs(product),
      agreedPriceKrw: line.finalPriceKrw,
      imageUrl: _image(product),
    );
  }

  static String _specs(ProductItem product) {
    final size = product.availableSizes.isEmpty
        ? null
        : product.availableSizes.first.toString();
    final weight = product.weightGrams;
    final parts = <String>[
      if (product.metal.trim().isNotEmpty) product.metal.trim(),
      if (weight != null && weight > 0) '${weight.toStringAsFixed(2)} г',
      if (size != null) 'размер $size',
    ];
    return parts.join(' · ');
  }

  static String? _image(ProductItem product) {
    if (product.images.isNotEmpty) return product.images.first;
    final url = product.imageUrl?.trim();
    return url == null || url.isEmpty ? null : url;
  }
}

class ReservationCheckoutResult {
  const ReservationCheckoutResult({required this.completed});

  final bool completed;
}

class ReservationCheckoutDialog extends StatefulWidget {
  const ReservationCheckoutDialog({
    super.key,
    required this.lines,
    required this.database,
    required this.sellerName,
    required this.sellerCode,
    required this.branch,
  });

  final List<ReservationCartLine> lines;
  final DatabaseService database;
  final String sellerName;
  final String sellerCode;
  final String branch;

  @override
  State<ReservationCheckoutDialog> createState() =>
      _ReservationCheckoutDialogState();
}

class _ReservationCheckoutDialogState extends State<ReservationCheckoutDialog> {
  static const _percents = <int>[10, 20, 30, 50];

  late String _paymentMethod;
  late String _branch;
  late DateTime _expiresAt;
  int? _percent;
  late int _deposit;
  var _busy = false;
  String? _error;

  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _commentController = TextEditingController();

  int get _total =>
      widget.lines.fold(0, (sum, line) => sum + line.agreedPriceKrw);

  int get _balance => (_total - _deposit).clamp(0, _total);

  @override
  void initState() {
    super.initState();
    _paymentMethod = reservationPaymentMethods.first;
    _branch = widget.branch.trim().toUpperCase();
    if (_branch != 'ICN' && _branch != 'ANS') _branch = 'ICN';
    _expiresAt = reservationPresetExpiry(7);
    _deposit = _percentOf(20);
    _percent = 20;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  int _percentOf(int percent) {
    final raw = (_total * percent / 100).round();
    if (_total <= 0) return 0;
    if (raw < 1) return 1;
    if (raw > _total) return _total;
    return raw;
  }

  void _setDeposit(int value, {int? percent}) {
    final next = value.clamp(0, _total);
    setState(() {
      _deposit = next;
      _percent = percent;
      _error = null;
    });
  }

  Future<void> _pickExpiry() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 366)),
      initialDate: _expiresAt,
      helpText: 'Срок брони',
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_expiresAt),
      helpText: 'Время окончания брони',
    );
    if (!mounted) return;
    final picked = time == null
        ? reservationEndOfDay(date)
        : DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() => _expiresAt = picked);
  }

  Future<void> _submit() async {
    if (_busy) return;
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    if (widget.lines.isEmpty) {
      setState(() => _error = 'В корзине нет изделий.');
      return;
    }
    if (_deposit <= 0 || _deposit > _total) {
      setState(() => _error = reservationErrorMessage('invalid_deposit'));
      return;
    }
    if (name.isEmpty || phone.isEmpty) {
      setState(() => _error = reservationErrorMessage('customer_required'));
      return;
    }
    if (!_expiresAt.isAfter(DateTime.now())) {
      setState(() => _error = reservationErrorMessage('invalid_expires_at'));
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.database.createReservation(
      lines: [
        for (final line in widget.lines)
          <String, dynamic>{
            'product_id': line.productId,
            'agreed_price_krw': line.agreedPriceKrw,
          },
      ],
      totalAmountKrw: _total,
      depositKrw: _deposit,
      paymentMethod: _paymentMethod,
      branch: _branch,
      sellerName: widget.sellerName,
      sellerCode: widget.sellerCode,
      customerName: name,
      customerPhone: phone,
      expiresAt: _expiresAt,
      comment: _commentController.text,
    );
    if (!mounted) return;
    if (result['ok'] == true) {
      Navigator.of(context).pop(
        ReservationCheckoutResult(completed: result['completed'] == true),
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
    final meta = AppTypography.productMeta();
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 680, maxHeight: height * 0.92),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Оформление брони по предоплате',
                      style: AppTypography.heading(fontSize: 18),
                    ),
                  ),
                  IconButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Состав заказа', style: AppTypography.productTitle),
                    const SizedBox(height: 8),
                    for (final line in widget.lines) _LineTile(line: line),
                    const SizedBox(height: 8),
                    ReservationMoneyRow(
                      label: 'Общая сумма заказа',
                      amount: _total,
                      emphasize: true,
                    ),
                    const SizedBox(height: 16),
                    Text('Сумма предоплаты / залога', style: meta),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final percent in _percents)
                          ChoiceChip(
                            label: Text('$percent%'),
                            selected: _percent == percent,
                            onSelected: _busy
                                ? null
                                : (_) => _setDeposit(
                                      _percentOf(percent),
                                      percent: percent,
                                    ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ReservationAmountField(
                      amount: _deposit,
                      enabled: !_busy,
                      label: 'Залог, ₩',
                      onChanged: (value) => _setDeposit(value),
                    ),
                    const SizedBox(height: 8),
                    ReservationMoneyRow(
                      label: 'Остаток к доплате',
                      amount: _balance,
                      emphasize: true,
                    ),
                    const SizedBox(height: 16),
                    Text('Способ оплаты залога', style: meta),
                    const SizedBox(height: 8),
                    ReservationPaymentPicker(
                      value: _paymentMethod,
                      enabled: !_busy,
                      onChanged: (value) => setState(() => _paymentMethod = value),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _branch,
                      decoration: const InputDecoration(
                        labelText: 'Филиал',
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
                    const SizedBox(height: 12),
                    TextField(
                      controller: _nameController,
                      enabled: !_busy,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Имя клиента',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _phoneController,
                      enabled: !_busy,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Телефон клиента',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('Срок действия брони', style: meta),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final days in const [3, 7, 14, 30])
                          ActionChip(
                            label: Text('+$days дн.'),
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                      _expiresAt = reservationPresetExpiry(days);
                                    }),
                          ),
                        ActionChip(
                          avatar: const Icon(Icons.event, size: 18),
                          label: Text(formatReservationWhen(_expiresAt)),
                          onPressed: _busy ? null : _pickExpiry,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _commentController,
                      enabled: !_busy,
                      minLines: 2,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Комментарий',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: meta.copyWith(color: AppColors.saleRed),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
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
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Оформить бронь'),
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

class _LineTile extends StatelessWidget {
  const _LineTile({required this.line});

  final ReservationCartLine line;

  @override
  Widget build(BuildContext context) {
    final meta = AppTypography.productMeta();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 52,
              height: 52,
              child: line.imageUrl == null
                  ? ColoredBox(
                      color: AppColors.cardBackground,
                      child: Icon(Icons.diamond_outlined, color: AppColors.textSecondary),
                    )
                  : Image.network(
                      line.imageUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const ColoredBox(
                        color: AppColors.cardBackground,
                        child: Icon(Icons.image_not_supported_outlined),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.sku, style: AppTypography.productTitle.copyWith(fontSize: 14)),
                if (line.title.isNotEmpty && line.title != line.sku)
                  Text(line.title, style: meta),
                if (line.specs.isNotEmpty) Text(line.specs, style: meta),
              ],
            ),
          ),
          KrwText(amount: line.agreedPriceKrw, style: meta, digitStyle: meta),
        ],
      ),
    );
  }
}
