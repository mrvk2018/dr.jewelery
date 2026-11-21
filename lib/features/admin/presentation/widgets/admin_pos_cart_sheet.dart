import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/services/database_service.dart';
import '../../../../shared/models/product_item.dart';
import '../../../../shared/models/seller_item.dart';
import '../../../profile/domain/models/user_profile.dart';
import '../../application/pos_cart_controller.dart';
import '../../domain/admin_pos_sale_exception.dart';
import '../../domain/models/pos_cart_item.dart';
import '../../domain/trade_in_scrap_draft.dart';
import '../screens/scrap_metal_intake_screen.dart';
import 'admin_pos_trade_in_section.dart';
import 'admin_product_photo_preview.dart';

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
    this.lockSellerSelection = false,
    this.presetSellerPromoCode,
    this.presetSellerName,
  });

  final PosCartController cart;
  final DatabaseService database;
  final Future<void> Function() onArchived;
  final bool lockSellerSelection;
  final String? presetSellerPromoCode;
  final String? presetSellerName;

  @override
  State<AdminPosCartSheet> createState() => _AdminPosCartSheetState();
}

class _AdminPosCartSheetState extends State<AdminPosCartSheet> {
  String _paymentMethod = AdminPosPaymentMethods.options.first;
  bool _checkoutBusy = false;
  bool _sellersLoading = true;
  List<SellerItem> _activeSellers = const [];
  String? _selectedPromoCode;
  String _storeLocation = 'ICN';

  @override
  void initState() {
    super.initState();
    _loadActiveSellers();
  }

  Future<void> _loadActiveSellers() async {
    try {
      if (widget.lockSellerSelection) {
        final code = widget.presetSellerPromoCode?.trim().toUpperCase();
        final name = widget.presetSellerName?.trim() ?? code ?? '';
        if (code != null && code.isNotEmpty) {
          setState(() {
            _activeSellers = [
              SellerItem(promoCode: code, name: name.isEmpty ? code : name),
            ];
            _selectedPromoCode = code;
            _sellersLoading = false;
          });
          return;
        }
      }
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
    final checkoutSkus = widget.cart.items
        .map((line) => line.product.sku)
        .where((sku) => sku.trim().isNotEmpty)
        .toList(growable: false);
    final seller = _selectedSeller!;
    try {
      final draft = widget.cart.tradeInDraft;
      final result = await widget.database.archiveAdminPosSale(
        lines: widget.cart.toSaleLineInputs(),
        sellerName: seller.name,
        sellerCode: seller.promoCode,
        paymentMethod: _paymentMethod,
        scrapTradeInPayload: draft?.scrapPayload,
        tradeInNetCashDeltaKrw: draft != null
            ? widget.cart.totalFinalKrw - draft.scrapTotalKrw
            : null,
        tradeInScrapTotalKrw: draft?.scrapTotalKrw,
      );
      if (!mounted) return;
      if (result.ok) {
        await widget.database.attachSellerToSales(
          skus: checkoutSkus,
          sellerCode: seller.promoCode,
          sellerName: seller.name,
        );
        Navigator.of(context).pop();
        widget.cart.clearCart();
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

  Future<void> _openTradeInScreen({TradeInScrapDraft? restore}) async {
    final cart = widget.cart;
    final seller = _selectedSeller;
    final result = await Navigator.of(context).push<TradeInScrapDraft>(
      MaterialPageRoute(
        builder: (_) => ScrapMetalIntakeScreen(
          database: widget.database,
          tradeInMode: true,
          cartTotalAmountKrw: cart.totalFinalKrw,
          initialPurchasedGoldWeightG: cart.cartGoldWeightGrams,
          initialStoreLocation: _storeLocation,
          initialSellerCode: seller?.promoCode,
          initialSellerName: seller?.name,
          initialTradeInDraft: restore,
        ),
      ),
    );
    if (result != null && mounted) {
      cart.attachTradeInDraft(result);
      setState(() => _storeLocation = result.storeLocation);
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
                              onPhotoTap: () => _openPosCartPhotoPreview(
                                context,
                                line,
                              ),
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
                    child: widget.lockSellerSelection
                        ? Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _checkoutSellerLabel.isEmpty
                                  ? '—'
                                  : _checkoutSellerLabel,
                              style: AppTypography.productName(),
                            ),
                          )
                        : _sellersLoading
                            ? const SizedBox(
                                height: 24,
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child:
                                        CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                ),
                              )
                            : DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  isExpanded: true,
                                  value: _activeSellers.any(
                                        (s) => s.promoCode == _selectedPromoCode,
                                      )
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
                                  onChanged:
                                      _checkoutBusy || _activeSellers.isEmpty
                                          ? null
                                          : (code) {
                                              if (code == null) return;
                                              setState(
                                                () => _selectedPromoCode = code,
                                              );
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
                      return AdminPosTradeInSection(
                        cart: cart,
                        storeLocation: _storeLocation,
                        checkoutBusy: _checkoutBusy,
                        onStoreChanged: (code) =>
                            setState(() => _storeLocation = code),
                        onOpenTradeIn: () => _openTradeInScreen(),
                        onEditTradeIn: () => _openTradeInScreen(
                          restore: cart.tradeInDraft,
                        ),
                        onRemoveTradeIn: cart.clearTradeInDraft,
                        onRecalculateTradeIn: () => _openTradeInScreen(
                          restore: cart.tradeInDraft,
                        ),
                      );
                    },
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
                              label: const Text('Оформить продажу'),
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

  Future<void> _openPosCartPhotoPreview(
    BuildContext context,
    PosCartItem line,
  ) async {
    final product = line.product;
    final urls = posCartProductImageUrls(product);
    if (urls.isEmpty) return;
    final subtitle = line.discountPercent <= 0
        ? '${_formatKrw(line.finalPriceKrw)} ₩'
        : '${_formatKrw(line.finalPriceKrw)} ₩ · −${line.discountPercent}%';
    await showAdminProductPhotoPreview(
      context,
      title: product.sku,
      subtitle: subtitle,
      imageUrls: urls,
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

List<String> posCartProductImageUrls(ProductItem product) {
  return posCartProductImageUrlsFromProduct(
    images: product.images,
    imageUrl: product.imageUrl,
  );
}

class _PosCartLineTile extends StatelessWidget {
  const _PosCartLineTile({
    super.key,
    required this.line,
    required this.onPhotoTap,
    required this.onDiscountChanged,
    required this.onRemove,
  });

  final PosCartItem line;
  final VoidCallback onPhotoTap;
  final ValueChanged<int> onDiscountChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final product = line.product;
    final photoUrls = posCartProductImageUrls(product);
    final hasPhoto = photoUrls.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _PosCartLineThumbnail(
            imageUrl: hasPhoto ? photoUrls.first : null,
            onTap: hasPhoto ? onPhotoTap : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.sku,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.productTitle.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                _PosCartLinePrice(line: line),
              ],
            ),
          ),
          const SizedBox(width: 8),
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              isDense: true,
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
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.delete_outline, color: AppColors.saleRed),
          ),
        ],
      ),
    );
  }
}

class _PosCartLinePrice extends StatelessWidget {
  const _PosCartLinePrice({required this.line});

  final PosCartItem line;

  @override
  Widget build(BuildContext context) {
    final finalText = '${_formatKrw(line.finalPriceKrw)} ₩';
    if (line.discountPercent <= 0) {
      return Text(finalText, style: AppTypography.productMeta());
    }
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 6,
      children: [
        Text(finalText, style: AppTypography.productMeta()),
        Text(
          '${_formatKrw(line.originalPriceKrw)} ₩',
          style: AppTypography.productMeta().copyWith(
            decoration: TextDecoration.lineThrough,
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          '−${line.discountPercent}%',
          style: AppTypography.productMeta().copyWith(
            color: AppColors.saleRed,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  String _formatKrw(int value) => value.toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]} ',
      );
}

class _PosCartLineThumbnail extends StatelessWidget {
  const _PosCartLineThumbnail({
    required this.imageUrl,
    this.onTap,
  });

  final String? imageUrl;
  final VoidCallback? onTap;

  static const _size = 56.0;

  @override
  Widget build(BuildContext context) {
    final child = DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: _size,
          height: _size,
          child: imageUrl == null
              ? _placeholder(Icons.diamond_outlined)
              : Image.network(
                  imageUrl!,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded /
                                  loadingProgress.expectedTotalBytes!
                              : null,
                        ),
                      ),
                    );
                  },
                  errorBuilder: (_, _, _) =>
                      _placeholder(Icons.image_not_supported_outlined),
                ),
        ),
      ),
    );

    if (onTap == null) return child;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Tooltip(
          message: 'Открыть фото крупно',
          child: child,
        ),
      ),
    );
  }

  Widget _placeholder(IconData icon) {
    return Center(
      child: Icon(
        icon,
        size: 26,
        color: AppColors.textSecondary.withValues(alpha: 0.55),
      ),
    );
  }
}

