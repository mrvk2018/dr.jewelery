import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/services/database_service.dart';
import '../../../../shared/models/seller_item.dart';
import '../../../profile/domain/models/user_profile.dart';
import '../../application/pos_cart_controller.dart';
import '../../domain/admin_pos_sale_exception.dart';
import '../../domain/models/pos_cart_item.dart';

abstract final class AdminPosPaymentMethods {
  static const options = <String>[
    'cash',
    'card',
    'transfer',
  ];

  static String label(String value) => switch (value) {
        'cash' => 'Наличные',
        'card' => 'Карта',
        'transfer' => 'Перевод',
        _ => value,
      };
}

class AdminPosCartSheet extends StatefulWidget {
  const AdminPosCartSheet({
    super.key,
    required this.cart,
    required this.database,
    required this.onArchived,
  });

  final PosCartController cart;
  final DatabaseService database;
  final Future<void> Function() onArchived;

  @override
  State<AdminPosCartSheet> createState() => _AdminPosCartSheetState();
}

class _AdminPosCartSheetState extends State<AdminPosCartSheet> {
  String _paymentMethod = AdminPosPaymentMethods.options.first;
  bool _checkoutBusy = false;
  bool _sellersLoading = true;
  List<SellerItem> _activeSellers = const [];
  String? _selectedPromoCode;

  @override
  void initState() {
    super.initState();
    _loadActiveSellers();
  }

  Future<void> _loadActiveSellers() async {
    try {
      final all =
          await widget.database.getSellers(UserRole.admin);
      if (!mounted) return;
      final active =
          all.where((s) => s.isActive).toList(growable: false)
            ..sort((a, b) => a.name.compareTo(b.name));
      setState(() {
        _activeSellers = active;
        _sellersLoading = false;
        if (active.isNotEmpty) {
          _selectedPromoCode ??= active.first.promoCode;
        }
      });
    } catch (error) {
      debugPrint('AdminPosCartSheet._loadActiveSellers: $error');
      if (mounted) setState(() => _sellersLoading = false);
    }
  }

  SellerItem? get _selectedSeller {
    final code = _selectedPromoCode;
    if (code == null) return null;
    for (final seller in _activeSellers) {
      if (seller.promoCode == code) return seller;
    }
    return null;
  }

  String get _checkoutSellerLabel {
    final seller = _selectedSeller;
    if (seller == null) return '';
    return '${seller.name} · ${seller.promoCode}';
  }

  Future<void> _archiveSale() async {
    if (_checkoutBusy || widget.cart.lineCount == 0) return;
    if (_selectedSeller == null) {
      await _showCheckoutError(
        const AdminPosSaleException(
          AdminPosSaleFailure.validation,
          message: 'Выберите продавца из списка',
        ),
      );
      return;
    }
    setState(() => _checkoutBusy = true);
    try {
      final result = await widget.database.archiveAdminPosSale(
        lines: widget.cart.toSaleLineInputs(),
        sellerName: _checkoutSellerLabel,
        paymentMethod: _paymentMethod,
      );
      if (!mounted) return;
      if (result.ok) {
        Navigator.of(context).pop();
        await widget.onArchived();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.orderId == null
                  ? 'POS-продажа заархивирована'
                  : 'POS-продажа · заказ ${result.orderId}',
            ),
          ),
        );
        return;
      }
      final error = result.error;
      if (error == null) return;
      await _showCheckoutError(error);
    } finally {
      if (mounted) setState(() => _checkoutBusy = false);
    }
  }

  Future<void> _showCheckoutError(AdminPosSaleException error) async {
    final isConcurrency =
        error.failure == AdminPosSaleFailure.concurrencyConflict;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isConcurrency ? 'Товар недоступен' : 'Ошибка оформления'),
        content: Text(error.userMessage),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = widget.cart;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Text(
                    'POS-корзина',
                    style: AppTypography.heading(fontSize: 18),
                  ),
                  const Spacer(),
                  IconButton(
                    tooltip: 'Закрыть',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            ListenableBuilder(
              listenable: cart,
              builder: (context, _) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (cart.lineCount == 0)
                      Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Добавьте изделия из таблицы кнопкой «В POS-корзину».',
                          style: AppTypography.productMeta(),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      Flexible(
                        child: ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: cart.items.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final line = cart.items[index];
                            return _PosCartLineTile(
                              key: ValueKey(
                                '${line.product.id}_${line.discountPercent}',
                              ),
                              line: line,
                              onDiscountChanged: (value) => cart.setLineDiscount(
                                line.product.id,
                                value,
                              ),
                              onRemove: () =>
                                  cart.removeFromCart(line.product.id),
                            );
                          },
                        ),
                      ),
                    const Divider(height: 1),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Итого',
                            style: AppTypography.heading(fontSize: 16),
                          ),
                          Text(
                            '${_formatKrw(cart.totalFinalKrw)} ₩',
                            style: AppTypography.heading(fontSize: 18),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Продавец',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      helperText: _sellersLoading
                          ? 'Загрузка картотеки…'
                          : _activeSellers.isEmpty
                              ? 'Нет активных сотрудников (Incheon: добавьте в «Управление персоналом»)'
                              : null,
                    ),
                    child: _sellersLoading
                        ? const SizedBox(
                            height: 24,
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          )
                        : DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              isExpanded: true,
                              value: _activeSellers
                                      .any((s) => s.promoCode == _selectedPromoCode)
                                  ? _selectedPromoCode
                                  : null,
                              hint: const Text('Выберите продавца'),
                              items: [
                                for (final seller in _activeSellers)
                                  DropdownMenuItem(
                                    value: seller.promoCode,
                                    child: Text(
                                      '${seller.name} · ${seller.promoCode}',
                                    ),
                                  ),
                              ],
                              onChanged: _checkoutBusy || _activeSellers.isEmpty
                                  ? null
                                  : (code) {
                                      if (code == null) return;
                                      setState(() => _selectedPromoCode = code);
                                    },
                            ),
                          ),
                  ),
                  const SizedBox(height: 12),
                  InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Способ оплаты',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        isExpanded: true,
                        value: _paymentMethod,
                        items: [
                          for (final method in AdminPosPaymentMethods.options)
                            DropdownMenuItem(
                              value: method,
                              child: Text(AdminPosPaymentMethods.label(method)),
                            ),
                        ],
                        onChanged: _checkoutBusy
                            ? null
                            : (value) {
                                if (value == null) return;
                                setState(() => _paymentMethod = value);
                              },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ListenableBuilder(
                    listenable: cart,
                    builder: (context, _) {
                      return Row(
                        children: [
                          OutlinedButton(
                            onPressed: _checkoutBusy || cart.lineCount == 0
                                ? null
                                : cart.clearCart,
                            child: const Text('Очистить'),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: _checkoutBusy || cart.lineCount == 0
                                  ? null
                                  : _archiveSale,
                              icon: _checkoutBusy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.point_of_sale_outlined),
                              label: const Text('Оформить продажу (Archive)'),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF1B5E20),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatKrw(int value) {
    final s = value.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

class _PosCartLineTile extends StatelessWidget {
  const _PosCartLineTile({
    super.key,
    required this.line,
    required this.onDiscountChanged,
    required this.onRemove,
  });

  final PosCartItem line;
  final ValueChanged<int> onDiscountChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final product = line.product;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        product.sku,
        style: AppTypography.productTitle.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${_formatKrw(line.finalPriceKrw)} ₩'
        '${line.discountPercent > 0 ? ' (−${line.discountPercent}%)' : ''}',
        style: AppTypography.productMeta(),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: line.discountPercent,
              items: [
                for (final pct in PosCartDiscountOptions.values)
                  DropdownMenuItem(value: pct, child: Text('−$pct%')),
              ],
              onChanged: (value) {
                if (value == null) return;
                onDiscountChanged(value);
              },
            ),
          ),
          IconButton(
            tooltip: 'Удалить из корзины',
            onPressed: onRemove,
            icon: Icon(Icons.delete_outline, color: AppColors.saleRed),
          ),
        ],
      ),
    );
  }

  String _formatKrw(int value) => value.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]} ',
      );
}
