import 'package:flutter/material.dart';

import '../../../../core/services/database_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/won_format.dart';
import '../../../printing/presentation/widgets/product_return_dialog.dart';
import '../../application/seller_terminal_service.dart';
import '../../data/seller_token_store.dart';
import '../../domain/seller_pos_pricing.dart';
import '../widgets/seller_qr_scanner.dart';

enum SellerSubMode { hub, pos, transferOut, transferIn }

/// Android POS-терминал: hub + изолированные режимы кассы и логистики.
class SellerTerminalScreen extends StatefulWidget {
  const SellerTerminalScreen({super.key});

  @override
  State<SellerTerminalScreen> createState() => _SellerTerminalScreenState();
}

class _SellerTerminalScreenState extends State<SellerTerminalScreen> {
  SellerTerminalService? _service;
  bool _bootstrapping = true;
  bool _accessRevoked = false;

  SellerSubMode _mode = SellerSubMode.hub;
  String? _activeShiftId;
  bool _busy = false;

  Map<String, dynamic>? _posProduct;
  int _discountPercent = 0;

  String _transferTo = 'ANS';
  final List<Map<String, dynamic>> _scannedOutItems = [];

  String _receiveStore = 'ICN';
  List<Map<String, dynamic>> _inboundTransfers = const [];
  final Set<String> _matchedInboundQr = {};

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

  void _checkRevoked(SellerTerminalService service) {
    if (service.consumeAccessRevoked()) {
      setState(() {
        _accessRevoked = true;
        _activeShiftId = null;
        _mode = SellerSubMode.hub;
        _posProduct = null;
        _scannedOutItems.clear();
        _inboundTransfers = const [];
        _matchedInboundQr.clear();
      });
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
    setState(() => _busy = true);
    try {
      final ok = await service.bindSellerCode(code);
      if (!mounted) return;
      _checkRevoked(service);
      if (_accessRevoked) return;
      if (!ok) {
        _snack('Код не найден или деактивирован', error: true);
        return;
      }
      setState(() {});
      _snack('Код ${service.sellerCode} сохранён');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startShift() async {
    final service = _service;
    if (service == null || service.sellerCode == null) return;
    setState(() => _busy = true);
    try {
      final id = await service.startShift();
      if (!mounted) return;
      _checkRevoked(service);
      if (_accessRevoked) return;
      if (id == null) {
        _snack('Не удалось начать смену (RLS / staff_shifts)', error: true);
        return;
      }
      setState(() => _activeShiftId = id);
      _snack('Смена начата');
    } catch (error) {
      _snack('Ошибка смены: $error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmEndShift() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Завершить смену?'),
        content: const Text('Кассовые и логистические режимы будут закрыты.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.saleRed),
            child: const Text('Завершить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _endShift();
  }

  Future<void> _endShift() async {
    final service = _service;
    final shiftId = _activeShiftId;
    if (service == null || shiftId == null) return;
    setState(() => _busy = true);
    try {
      final ok = await service.endShift(shiftId);
      if (!mounted) return;
      _checkRevoked(service);
      if (_accessRevoked) return;
      if (!ok) {
        _snack('Не удалось завершить смену', error: true);
        return;
      }
      setState(() {
        _activeShiftId = null;
        _mode = SellerSubMode.hub;
        _posProduct = null;
        _scannedOutItems.clear();
        _matchedInboundQr.clear();
      });
      _snack('Смена завершена');
    } catch (error) {
      _snack('Ошибка: $error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _goHub() {
    setState(() {
      _mode = SellerSubMode.hub;
      _posProduct = null;
    });
  }

  Future<void> _enterTransferIn() async {
    final service = _service;
    if (service == null) return;
    setState(() {
      _mode = SellerSubMode.transferIn;
      _matchedInboundQr.clear();
      _busy = true;
    });
    try {
      final rows = await service.loadInboundTransfers(_receiveStore);
      if (!mounted) return;
      _checkRevoked(service);
      setState(() => _inboundTransfers = rows);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onPosQr(String payload) async {
    final service = _service;
    if (service == null) return;
    setState(() => _busy = true);
    try {
      final product = await service.loadProductByQr(payload);
      if (!mounted) return;
      _checkRevoked(service);
      if (_accessRevoked) return;
      if (product == null) {
        _snack('Товар не найден по QR', error: true);
        return;
      }
      setState(() {
        _posProduct = product;
        _discountPercent = 0;
      });
    } catch (error) {
      _snack('Загрузка: $error', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onTransferOutQr(String payload) async {
    final service = _service;
    if (service == null) return;
    setState(() => _busy = true);
    try {
      final product = await service.loadProductByQr(payload);
      if (!mounted) return;
      _checkRevoked(service);
      if (_accessRevoked) return;
      if (product == null) {
        _snack('Товар не найден', error: true);
        return;
      }
      final sku = product['sku']?.toString() ?? '';
      if (_scannedOutItems.any((row) => row['sku']?.toString() == sku)) {
        _snack('SKU уже в накладной', error: true);
        return;
      }
      setState(() => _scannedOutItems.add(Map<String, dynamic>.from(product)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onTransferInQr(String payload) async {
    final service = _service;
    if (service == null) return;
    setState(() => _busy = true);
    try {
      final product = await service.loadProductByQr(payload);
      if (!mounted) return;
      _checkRevoked(service);
      if (_accessRevoked) return;
      if (product == null) {
        _snack('Товар не найден', error: true);
        return;
      }
      final sku = product['sku']?.toString() ?? '';
      final qr = product['qr_code_payload']?.toString() ?? sku;
      final inList = _inboundTransfers.any((row) {
        final rowSku = row['sku']?.toString() ?? '';
        final rowQr = row['qr_code_payload']?.toString() ?? rowSku;
        return rowSku == sku || rowQr == qr || rowQr == payload;
      });
      if (!inList) {
        _snack('Нет в списке входящих в $_receiveStore', error: true);
        return;
      }
      setState(() => _matchedInboundQr.add(qr));
      _snack('Совпадение · $sku');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  SellerPosPricing get _quote {
    final product = _posProduct;
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
    final product = _posProduct;
    if (service == null || product == null) {
      _snack('Сначала отсканируйте товар', error: true);
      return;
    }
    final qr = product['qr_code_payload']?.toString() ?? '';
    if (qr.isEmpty) {
      _snack('Нет qr_code_payload', error: true);
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
      _checkRevoked(service);
      if (_accessRevoked) return;
      if (result['ok'] != true) {
        _snack('Продажа: ${result['error'] ?? result}', error: true);
        return;
      }
      _snack('Продажа · ${formatWon(_quote.totalKrw)}');
      setState(() => _posProduct = null);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmTransferOutBatch() async {
    final service = _service;
    if (service == null || _scannedOutItems.isEmpty) return;
    setState(() => _busy = true);
    var okCount = 0;
    try {
      for (final item in _scannedOutItems) {
        final qr = item['qr_code_payload']?.toString() ?? '';
        if (qr.isEmpty) continue;
        final result = await service.sendTransfer(
          qrPayload: qr,
          toLocation: _transferTo,
        );
        if (!mounted) return;
        _checkRevoked(service);
        if (_accessRevoked) return;
        if (result['ok'] == true) okCount++;
      }
      _snack('Отправлено $okCount из ${_scannedOutItems.length} → $_transferTo');
      setState(() => _scannedOutItems.clear());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showCustomerOrderAlert(String alert) {
    return showDialog<void>(
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
  }

  Future<void> _confirmTransferInBatch() async {
    final service = _service;
    if (service == null || _matchedInboundQr.isEmpty) {
      _snack('Отсканируйте товары из списка', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      for (final qr in _matchedInboundQr.toList()) {
        final result = await service.receiveTransfer(qr);
        if (!mounted) return;
        _checkRevoked(service);
        if (_accessRevoked) return;
        if (result['ok'] != true) {
          _snack('Приём: ${result['error'] ?? result}', error: true);
          continue;
        }
        final alert = result['alert']?.toString();
        if (alert != null && alert.isNotEmpty) {
          await _showCustomerOrderAlert(alert);
        }
      }
      _snack('Приёмка завершена');
      await _enterTransferIn();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _isInboundMatched(Map<String, dynamic> row) {
    final sku = row['sku']?.toString() ?? '';
    final qr = row['qr_code_payload']?.toString() ?? sku;
    return _matchedInboundQr.contains(qr) || _matchedInboundQr.contains(sku);
  }

  @override
  Widget build(BuildContext context) {
    if (_bootstrapping) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_accessRevoked) {
      return _AccessRevokedScreen(
        onAcknowledge: () => setState(() => _accessRevoked = false),
      );
    }

    final service = _service!;
    if (service.sellerCode == null) {
      return _BindSellerScreen(
        controller: _bindController,
        busy: _busy,
        onSave: _bindSeller,
      );
    }

    final shiftOpen = _activeShiftId != null;

    return Stack(
      children: [
        switch (_mode) {
          SellerSubMode.hub => _HubScreen(
              sellerCode: service.sellerCode!,
              shiftOpen: shiftOpen,
              busy: _busy,
              onStartShift: _startShift,
              onEndShift: _confirmEndShift,
              onOpenPos: shiftOpen
                  ? () => setState(() => _mode = SellerSubMode.pos)
                  : null,
              onOpenTransferOut: shiftOpen
                  ? () => setState(() {
                        _mode = SellerSubMode.transferOut;
                        _scannedOutItems.clear();
                      })
                  : null,
              onOpenTransferIn: shiftOpen ? _enterTransferIn : null,
            ),
          SellerSubMode.pos => _PosScreen(
              sellerCode: service.sellerCode!,
              busy: _busy,
              product: _posProduct,
              quote: _quote,
              discountPercent: _discountPercent,
              onBack: _goHub,
              onQr: _onPosQr,
              onDiscountChanged: (v) => setState(() => _discountPercent = v),
              onConfirmSale: _confirmSale,
              onOpenReturn: () => ProductReturnDialog.show(
                context,
                database: service.database,
              ),
            ),
          SellerSubMode.transferOut => _TransferOutScreen(
              busy: _busy,
              transferTo: _transferTo,
              items: _scannedOutItems,
              onBack: _goHub,
              onDestinationChanged: (v) => setState(() => _transferTo = v),
              onQr: _onTransferOutQr,
              onRemoveAt: (index) =>
                  setState(() => _scannedOutItems.removeAt(index)),
              onConfirmBatch: _confirmTransferOutBatch,
            ),
          SellerSubMode.transferIn => _TransferInScreen(
              busy: _busy,
              receiveStore: _receiveStore,
              inbound: _inboundTransfers,
              isMatched: _isInboundMatched,
              matchedCount: _matchedInboundQr.length,
              onBack: _goHub,
              onStoreChanged: (store) async {
                setState(() => _receiveStore = store);
                await _enterTransferIn();
              },
              onQr: _onTransferInQr,
              onConfirmBatch: _confirmTransferInBatch,
            ),
        },
        if (_busy)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 3),
          ),
      ],
    );
  }
}

class _AccessRevokedScreen extends StatelessWidget {
  const _AccessRevokedScreen({required this.onAcknowledge});

  final VoidCallback onAcknowledge;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.saleRed,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.block, size: 72, color: AppColors.textOnPrimary),
              const SizedBox(height: 24),
              Text(
                'ДОСТУП АННУЛИРОВАН.\nСВЯЖИТЕСЬ С АДМИНИСТРАТОРОМ',
                textAlign: TextAlign.center,
                style: AppTypography.heading(fontSize: 22).copyWith(
                  color: AppColors.textOnPrimary,
                ),
              ),
              const SizedBox(height: 32),
              FilledButton(
                onPressed: onAcknowledge,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.textOnPrimary,
                  foregroundColor: AppColors.saleRed,
                ),
                child: const Text('Понятно'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BindSellerScreen extends StatelessWidget {
  const _BindSellerScreen({
    required this.controller,
    required this.busy,
    required this.onSave,
  });

  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Привязка продавца')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Личный код продавца', style: AppTypography.heading(fontSize: 22)),
            const SizedBox(height: 8),
            Text(
              'Код проверяется в Supabase (is_active).',
              style: AppTypography.productMeta(),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: controller,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'AEU-256',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy ? null : onSave,
              child: const Text('Сохранить код'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HubScreen extends StatelessWidget {
  const _HubScreen({
    required this.sellerCode,
    required this.shiftOpen,
    required this.busy,
    required this.onStartShift,
    required this.onEndShift,
    required this.onOpenPos,
    required this.onOpenTransferOut,
    required this.onOpenTransferIn,
  });

  final String sellerCode;
  final bool shiftOpen;
  final bool busy;
  final VoidCallback onStartShift;
  final VoidCallback onEndShift;
  final VoidCallback? onOpenPos;
  final VoidCallback? onOpenTransferOut;
  final VoidCallback? onOpenTransferIn;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Терминал · $sellerCode')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.circle,
                      size: 12,
                      color: shiftOpen ? Colors.green : AppColors.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        shiftOpen ? 'Смена открыта' : 'Смена закрыта',
                        style: AppTypography.productMeta(),
                      ),
                    ),
                    Text('AEU: $sellerCode', style: AppTypography.productMeta()),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (!shiftOpen) ...[
              FilledButton(
                onPressed: busy ? null : onStartShift,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  backgroundColor: Colors.green.shade700,
                ),
                child: const Text(
                  '🟢 НАЧАТЬ РАБОЧУЮ СМЕНУ',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 16),
              _HubTile(
                emoji: '🛒',
                title: '1. ОФОРМИТЬ ПРОДАЖУ / ВОЗВРАТ',
                enabled: false,
                onTap: () {},
              ),
              const SizedBox(height: 12),
              _HubTile(
                emoji: '🚚',
                title: '2. ОТПРАВИТЬ ТРАНСФЕР (НИНА)',
                enabled: false,
                onTap: () {},
              ),
              const SizedBox(height: 12),
              _HubTile(
                emoji: '📦',
                title: '3. ПРИНЯТЬ ТРАНСФЕР (МАРИЯ)',
                enabled: false,
                onTap: () {},
              ),
            ] else ...[
              _HubTile(
                emoji: '🛒',
                title: '1. ОФОРМИТЬ ПРОДАЖУ / ВОЗВРАТ',
                enabled: true,
                onTap: onOpenPos!,
              ),
              const SizedBox(height: 12),
              _HubTile(
                emoji: '🚚',
                title: '2. ОТПРАВИТЬ ТРАНСФЕР (НИНА)',
                enabled: true,
                onTap: onOpenTransferOut!,
              ),
              const SizedBox(height: 12),
              _HubTile(
                emoji: '📦',
                title: '3. ПРИНЯТЬ ТРАНСФЕР (МАРИЯ)',
                enabled: true,
                onTap: onOpenTransferIn!,
              ),
            ],
            const Spacer(),
            if (shiftOpen)
              OutlinedButton(
                onPressed: busy ? null : onEndShift,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.saleRed,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('🔴 ЗАВЕРШИТЬ СМЕНУ'),
              ),
          ],
        ),
      ),
    );
  }
}

class _HubTile extends StatelessWidget {
  const _HubTile({
    required this.emoji,
    required this.title,
    required this.enabled,
    required this.onTap,
  });

  final String emoji;
  final String title;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: enabled
          ? AppColors.primary.withValues(alpha: 0.08)
          : AppColors.cardBackground,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: enabled ? AppColors.primary : AppColors.border,
              width: enabled ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.heading(fontSize: 16).copyWith(
                    color: enabled
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: enabled ? AppColors.primary : AppColors.border,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PosScreen extends StatelessWidget {
  const _PosScreen({
    required this.sellerCode,
    required this.busy,
    required this.product,
    required this.quote,
    required this.discountPercent,
    required this.onBack,
    required this.onQr,
    required this.onDiscountChanged,
    required this.onConfirmSale,
    required this.onOpenReturn,
  });

  final String sellerCode;
  final bool busy;
  final Map<String, dynamic>? product;
  final SellerPosPricing quote;
  final int discountPercent;
  final VoidCallback onBack;
  final ValueChanged<String> onQr;
  final ValueChanged<int> onDiscountChanged;
  final VoidCallback onConfirmSale;
  final VoidCallback onOpenReturn;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Text('⬅️', style: TextStyle(fontSize: 20)),
          onPressed: busy ? null : onBack,
        ),
        title: Text('Касса · $sellerCode'),
        actions: [
          TextButton.icon(
            onPressed: busy ? null : onOpenReturn,
            icon: const Icon(Icons.replay_outlined),
            label: const Text('Возврат'),
          ),
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SellerQrScanner(onDetected: onQr),
                const SizedBox(height: 12),
                if (product != null)
                  _ProductCard(
                    product: product!,
                    discountPercent: discountPercent,
                    onDiscountChanged: onDiscountChanged,
                    quote: quote,
                  ),
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
                      onPressed: busy ? null : onConfirmSale,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
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
        ],
      ),
    );
  }
}

class _TransferOutScreen extends StatelessWidget {
  const _TransferOutScreen({
    required this.busy,
    required this.transferTo,
    required this.items,
    required this.onBack,
    required this.onDestinationChanged,
    required this.onQr,
    required this.onRemoveAt,
    required this.onConfirmBatch,
  });

  final bool busy;
  final String transferTo;
  final List<Map<String, dynamic>> items;
  final VoidCallback onBack;
  final ValueChanged<String> onDestinationChanged;
  final ValueChanged<String> onQr;
  final ValueChanged<int> onRemoveAt;
  final VoidCallback onConfirmBatch;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Text('⬅️', style: TextStyle(fontSize: 20)),
          onPressed: busy ? null : onBack,
        ),
        title: const Text('Отправка трансфера'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: DropdownButtonFormField<String>(
              initialValue: transferTo,
              decoration: const InputDecoration(
                labelText: 'Куда: ICN / ANS',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'ICN', child: Text('ICN')),
                DropdownMenuItem(value: 'ANS', child: Text('ANS')),
              ],
              onChanged: busy ? null : (v) => onDestinationChanged(v ?? transferTo),
            ),
          ),
          SizedBox(
            height: 160,
            child: SellerQrScanner(onDetected: onQr),
          ),
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text(
                      'Сканируйте товары в накладную',
                      style: AppTypography.productMeta(),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final row = items[index];
                      final sku = row['sku']?.toString() ?? '—';
                      final weight =
                          (row['weight_grams'] as num?)?.toStringAsFixed(2) ??
                              '—';
                      return ListTile(
                        title: Text(sku),
                        subtitle: Text('Вес: $weight г'),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: busy ? null : () => onRemoveAt(index),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: busy || items.isEmpty ? null : onConfirmBatch,
                  child: Text(
                    'ПОДТВЕРДИТЬ И ОТПРАВИТЬ НАКЛАДНУЮ (${items.length} шт)',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TransferInScreen extends StatelessWidget {
  const _TransferInScreen({
    required this.busy,
    required this.receiveStore,
    required this.inbound,
    required this.isMatched,
    required this.matchedCount,
    required this.onBack,
    required this.onStoreChanged,
    required this.onQr,
    required this.onConfirmBatch,
  });

  final bool busy;
  final String receiveStore;
  final List<Map<String, dynamic>> inbound;
  final bool Function(Map<String, dynamic> row) isMatched;
  final int matchedCount;
  final VoidCallback onBack;
  final ValueChanged<String> onStoreChanged;
  final ValueChanged<String> onQr;
  final VoidCallback onConfirmBatch;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Text('⬅️', style: TextStyle(fontSize: 20)),
          onPressed: busy ? null : onBack,
        ),
        title: const Text('Приёмка трансфера'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            child: DropdownButtonFormField<String>(
              initialValue: receiveStore,
              decoration: const InputDecoration(
                labelText: 'Магазин приёмки',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'ICN', child: Text('ICN')),
                DropdownMenuItem(value: 'ANS', child: Text('ANS')),
              ],
              onChanged: busy ? null : (v) => onStoreChanged(v ?? receiveStore),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'В пути · ${inbound.length} поз.',
              style: AppTypography.heading(fontSize: 16),
            ),
          ),
          SizedBox(
            height: 120,
            child: SellerQrScanner(onDetected: onQr),
          ),
          Expanded(
            child: inbound.isEmpty
                ? Center(
                    child: Text(
                      'Нет входящих в $receiveStore',
                      style: AppTypography.productMeta(),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: inbound.length,
                    itemBuilder: (context, index) {
                      final row = inbound[index];
                      final sku = row['sku']?.toString() ?? '—';
                      final from = row['from_store']?.toString() ?? '—';
                      final matched = isMatched(row);
                      return ListTile(
                        leading: Icon(
                          matched ? Icons.check_circle : Icons.local_shipping_outlined,
                          color: matched ? Colors.green : AppColors.textSecondary,
                        ),
                        title: Text(sku),
                        subtitle: Text('Из $from → $receiveStore'),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: busy || matchedCount == 0 ? null : onConfirmBatch,
                  child: Text('ПОДТВЕРДИТЬ ПРИЕМКУ ($matchedCount)'),
                ),
              ),
            ),
          ),
        ],
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
                        (p) => DropdownMenuItem(value: p, child: Text('$p%')),
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
