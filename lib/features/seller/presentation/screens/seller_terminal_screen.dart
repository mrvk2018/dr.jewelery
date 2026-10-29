import 'package:flutter/material.dart';

import '../../../../core/services/database_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/won_format.dart';
import '../../application/seller_terminal_service.dart';
import '../../data/seller_token_store.dart';
import '../../domain/seller_pos_pricing.dart';
import '../widgets/seller_qr_scanner.dart';

/// Android POS-терминал продавца: смена, QR-касса, трансферы ICN ↔ ANS.
class SellerTerminalScreen extends StatefulWidget {
  const SellerTerminalScreen({super.key});

  @override
  State<SellerTerminalScreen> createState() => _SellerTerminalScreenState();
}

class _SellerTerminalScreenState extends State<SellerTerminalScreen> {
  SellerTerminalService? _service;
  bool _bootstrapping = true;

  String? _activeShiftId;
  Map<String, dynamic>? _product;
  int _discountPercent = 0;
  String _transferTo = 'ANS';
  bool _busy = false;

  final _bindController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _bindController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final store = await SellerTokenStore.create();
      final service = SellerTerminalService(
        database: DatabaseService.create(),
        tokenStore: store,
      );
      if (!mounted) return;
      setState(() {
        _service = service;
        _bootstrapping = false;
      });
    } catch (error, stackTrace) {
      debugPrint('SellerTerminalScreen._bootstrap failed: $error');
      debugPrint('$stackTrace');
      if (mounted) setState(() => _bootstrapping = false);
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

  Future<void> _bindSeller() async {
    final service = _service;
    if (service == null) return;
    final code = _bindController.text.trim();
    if (code.isEmpty) {
      _snack('Введите код продавца (AEU-256)', error: true);
      return;
    }
    await service.bindSellerCode(code);
    if (!mounted) return;
    setState(() {});
    _snack('Код ${service.sellerCode} сохранён на устройстве');
  }

  Future<void> _startShift() async {
    final service = _service;
    if (service == null || service.sellerCode == null) return;
    setState(() => _busy = true);
    try {
      final id = await service.startShift();
      if (!mounted) return;
      if (id == null) {
        _snack('Не удалось начать смену (RLS / staff_shifts)', error: true);
        return;
      }
      setState(() => _activeShiftId = id);
      _snack('Смена начата · Realtime для админки');
    } catch (error) {
      _snack('Ошибка смены: $error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _endShift() async {
    final service = _service;
    final shiftId = _activeShiftId;
    if (service == null || shiftId == null) return;
    setState(() => _busy = true);
    try {
      final ok = await service.endShift(shiftId);
      if (!mounted) return;
      if (!ok) {
        _snack('Не удалось завершить смену', error: true);
        return;
      }
      setState(() => _activeShiftId = null);
      _snack('Смена завершена');
    } catch (error) {
      _snack('Ошибка: $error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onQrScanned(String payload) async {
    final service = _service;
    if (service == null) return;
    setState(() => _busy = true);
    try {
      final product = await service.loadProductByQr(payload);
      if (!mounted) return;
      if (product == null) {
        _snack('Товар не найден по QR', error: true);
        return;
      }
      final store = product['store_location']?.toString().toUpperCase();
      setState(() {
        _product = product;
        _discountPercent = 0;
        _transferTo = store == 'ICN' ? 'ANS' : 'ICN';
      });
    } catch (error) {
      _snack('Загрузка товара: $error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  SellerPosPricing get _quote {
    final product = _product;
    if (product == null) {
      return SellerPosPricing.quote(basePriceKrw: 0, discountPercent: 0);
    }
    return SellerPosPricing.quote(
      basePriceKrw: SellerTerminalService.readBasePriceKrw(product),
      discountPercent: _discountPercent,
    );
  }

  Future<void> _confirmSale() async {
    final service = _service;
    final product = _product;
    if (service == null || product == null) {
      _snack('Сначала отсканируйте товар', error: true);
      return;
    }
    final qr = product['qr_code_payload']?.toString() ?? '';
    if (qr.isEmpty) {
      _snack('У товара нет qr_code_payload', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await service.confirmSale(
        qrPayload: qr,
        basePriceKrw: SellerTerminalService.readBasePriceKrw(product),
        discountPercent: _discountPercent,
      );
      if (!mounted) return;
      if (result['ok'] != true) {
        _snack('Продажа отклонена: ${result['error'] ?? result}', error: true);
        return;
      }
      _snack('Продажа подтверждена · ${formatWon(_quote.totalKrw)}');
      setState(() => _product = null);
    } catch (error) {
      _snack('RPC process_pos_qr_sale: $error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendTransfer() async {
    final service = _service;
    final product = _product;
    if (service == null || product == null) return;
    final qr = product['qr_code_payload']?.toString() ?? '';
    if (qr.isEmpty) return;

    setState(() => _busy = true);
    try {
      final result = await service.sendTransfer(
        qrPayload: qr,
        toLocation: _transferTo,
      );
      if (!mounted) return;
      if (result['ok'] != true) {
        _snack('Трансфер: ${result['error'] ?? result}', error: true);
        return;
      }
      _snack('Отправлено в $_transferTo · stock_quantity заблокирован');
      setState(() => _product = null);
    } catch (error) {
      _snack('initiate_product_transfer: $error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _receiveTransfer() async {
    final service = _service;
    final product = _product;
    if (service == null || product == null) return;
    final qr = product['qr_code_payload']?.toString() ?? '';
    if (qr.isEmpty) return;

    setState(() => _busy = true);
    try {
      final result = await service.receiveTransfer(qr);
      if (!mounted) return;
      if (result['ok'] != true) {
        _snack('Приём: ${result['error'] ?? result}', error: true);
        return;
      }
      final alert = result['alert']?.toString();
      if (alert != null && alert.isNotEmpty) {
        await showDialog<void>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(
              'ВНИМАНИЕ КАССЫ',
              style: AppTypography.heading(fontSize: 20).copyWith(
                color: AppColors.saleRed,
              ),
            ),
            content: Text(
              'ОТЛОЖИТЬ НА СПЕЦ-ПОЛКУ ДЛЯ ВЫДАЧИ\n\n$alert',
              style: AppTypography.productName().copyWith(fontSize: 16),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Понятно'),
              ),
            ],
          ),
        );
      } else {
        _snack('Трансфер принят · товар на витрине');
      }
      setState(() => _product = null);
    } catch (error) {
      _snack('complete_product_transfer: $error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_bootstrapping) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final service = _service!;
    if (service.sellerCode == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Привязка продавца')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Личный код продавца',
                style: AppTypography.heading(fontSize: 22),
              ),
              const SizedBox(height: 8),
              Text(
                'Код сохраняется на устройстве (SharedPreferences) и '
                'не запрашивается при следующих запусках.',
                style: AppTypography.productMeta(),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _bindController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'AEU-256',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _bindSeller,
                child: const Text('Сохранить код'),
              ),
            ],
          ),
        ),
      );
    }

    final product = _product;
    final quote = _quote;

    return Scaffold(
      appBar: AppBar(
        title: Text('Касса · ${service.sellerCode}'),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ShiftBar(
                  shiftActive: _activeShiftId != null,
                  busy: _busy,
                  onStart: _startShift,
                  onEnd: _endShift,
                ),
                const SizedBox(height: 12),
                SellerQrScanner(onDetected: _onQrScanned),
                const SizedBox(height: 12),
                if (product != null) ...[
                  _ProductCard(
                    product: product,
                    discountPercent: _discountPercent,
                    onDiscountChanged: (value) {
                      setState(() => _discountPercent = value);
                    },
                    quote: quote,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _transferTo,
                          decoration: const InputDecoration(
                            labelText: 'Куда отправить',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'ICN', child: Text('ICN')),
                            DropdownMenuItem(value: 'ANS', child: Text('ANS')),
                          ],
                          onChanged: _busy
                              ? null
                              : (value) {
                                  if (value != null) {
                                    setState(() => _transferTo = value);
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton(
                        onPressed: _busy ? null : _sendTransfer,
                        child: const Text('Отправить в другой магазин'),
                      ),
                      OutlinedButton(
                        onPressed: _busy ? null : _receiveTransfer,
                        child: const Text('Принять трансфер'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 80),
              ],
            ),
          ),
          if (product != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _busy ? null : _confirmSale,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.textOnAccent,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: Text(
                        'Подтвердить продажу · ${formatWon(quote.totalKrw)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_busy)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(minHeight: 3),
            ),
        ],
      ),
    );
  }
}

class _ShiftBar extends StatelessWidget {
  const _ShiftBar({
    required this.shiftActive,
    required this.busy,
    required this.onStart,
    required this.onEnd,
  });

  final bool shiftActive;
  final bool busy;
  final VoidCallback onStart;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(
              Icons.circle,
              size: 12,
              color: shiftActive ? Colors.green : AppColors.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                shiftActive ? 'Смена активна' : 'Смена не начата',
                style: AppTypography.productMeta(),
              ),
            ),
            FilledButton.tonal(
              onPressed: busy || shiftActive ? null : onStart,
              child: const Text('Начать смену'),
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              onPressed: busy || !shiftActive ? null : onEnd,
              child: const Text('Завершить смену'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.discountPercent,
    required this.onDiscountChanged,
    required this.quote,
  });

  final Map<String, dynamic> product;
  final int discountPercent;
  final ValueChanged<int> onDiscountChanged;
  final SellerPosPricing quote;

  @override
  Widget build(BuildContext context) {
    final base = SellerTerminalService.readBasePriceKrw(product);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              product['sku']?.toString() ?? '—',
              style: AppTypography.heading(fontSize: 20),
            ),
            const SizedBox(height: 8),
            Text('Металл: ${product['metal_type'] ?? '—'}'),
            Text(
              'Вес: ${(product['weight_grams'] as num?)?.toStringAsFixed(2) ?? '—'} г',
            ),
            Text('Вставки: ${product['gem_inserts'] ?? '—'}'),
            const SizedBox(height: 12),
            Text('Базовая цена: ${formatWon(base)}'),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Скидка',
                border: OutlineInputBorder(),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: discountPercent,
                  items: SellerPosPricing.discountOptions
                      .map(
                        (p) => DropdownMenuItem(
                          value: p,
                          child: Text('$p%'),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) onDiscountChanged(value);
                  },
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text('После скидки: ${formatWon(quote.discountedPriceKrw)}'),
            Text(
              'Доставка: ${formatWon(quote.deliveryFeeKrw)}',
              style: AppTypography.productMeta(),
            ),
            Text(
              'Итого: ${formatWon(quote.totalKrw)}',
              style: AppTypography.heading(fontSize: 18),
            ),
          ],
        ),
      ),
    );
  }
}
