import 'package:flutter/material.dart';

import '../../../checkout/domain/models/shipping_address.dart';
import '../../../../core/constants/merchant_legal_info.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/services/payment_service.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/l10n/payment_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/won_format.dart';
import '../../../../shared/providers/cart_controller.dart';
import '../../../../shared/providers/cart_scope.dart';
import '../../../../shared/providers/catalog_scope.dart';
import '../../../../shared/providers/profile_scope.dart';
import '../../../profile/domain/models/order_item.dart';
import '../../domain/models/payment_models.dart';
import '../widgets/payment_loading_overlay.dart';
import 'payment_success_screen.dart';
import 'toss_web_view_page.dart';

/// Экран оплаты через Toss Payments Widget (выбор способа — внутри WebView).
class PaymentScreen extends StatefulWidget {
  const PaymentScreen({
    super.key,
    required this.productsTotalKrw,
    required this.deliveryFeeKrw,
    required this.shippingAddress,
    this.checkoutItems,
    this.sellerCode = '',
  });

  final int productsTotalKrw;
  final int deliveryFeeKrw;
  final ShippingAddress shippingAddress;

  /// Линии заказа для резерва склада и уведомлений. `null` → вся корзина.
  final List<CartItem>? checkoutItems;

  /// Промокод продавца после apply_seller_referral_promo на checkout.
  final String sellerCode;

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  String? _validationMessage;
  bool _isConfirmingPayment = false;
  bool _isTermsAccepted = false;

  String tr(String key) => paymentTr(key, context.langCode);

  String get _totalLabel {
    final products = formatWon(widget.productsTotalKrw);
    if (widget.deliveryFeeKrw > 0) {
      return '${tr(PaymentStringKeys.totalToPay)}: $products + ${formatWon(widget.deliveryFeeKrw)}';
    }
    return '${tr(PaymentStringKeys.totalToPay)}: $products';
  }

  List<CartItem> get _checkoutLineItems {
    if (widget.checkoutItems != null && widget.checkoutItems!.isNotEmpty) {
      return widget.checkoutItems!;
    }
    return CartScope.of(context).items;
  }

  Future<void> _showRetailSoldDialog() {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(tr(PaymentStringKeys.soldOutTitle)),
        content: Text(tr(PaymentStringKeys.soldOutMessage)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(tr(PaymentStringKeys.soldOutOk)),
          ),
        ],
      ),
    );
  }

  Future<bool> _verifySkladAndReserveCart() async {
    final database = CatalogScope.of(context).database;
    final items = _checkoutLineItems;
    if (items.isEmpty) return false;

    for (final item in items) {
      final available =
          await database.checkSkladAvailability(item.product.sku);
      if (!available) return false;
    }

    for (final item in items) {
      final reserved =
          await database.reserveProductForCheckout(item.product.id);
      if (!reserved) return false;
    }

    if (!mounted) return false;
    await CatalogScope.of(context).load();
    return true;
  }

  Future<void> _releaseReservedCart() async {
    final database = CatalogScope.of(context).database;
    for (final item in _checkoutLineItems) {
      try {
        await database.releaseProductCheckout(item.product.id);
      } catch (error, stackTrace) {
        debugPrint(
          'releaseProductCheckout id=${item.product.id}: $error',
        );
        debugPrint('$stackTrace');
      }
    }
  }

  OrderItem _buildPaidOrderItem({
    required String orderId,
    required int totalAmountKrw,
    required List<CartItem> purchased,
  }) {
    final profile = ProfileScope.of(context);
    final languageCode = context.langCode;
    final names = purchased
        .map(
          (item) =>
              item.product.nameTranslations[languageCode] ??
              item.product.nameTranslations['ru'] ??
              item.product.sku,
        )
        .join(', ');
    final now = DateTime.now();
    const months = [
      'янв',
      'фев',
      'мар',
      'апр',
      'май',
      'июн',
      'июл',
      'авг',
      'сен',
      'окт',
      'ноя',
      'дек',
    ];
    final shipping = widget.shippingAddress;
    return OrderItem(
      id: orderId,
      productName: names,
      amount: totalAmountKrw,
      status: OrderStatus.paid,
      dateLabel: '${now.day} ${months[now.month - 1]} ${now.year}',
      customerName: profile.user.name.isEmpty
          ? shipping.recipientName
          : profile.user.name,
      shippingPostalCode: shipping.postalCode,
      shippingRoadAddress: shipping.roadAddress,
      shippingDetailAddress: shipping.detailAddress,
      recipientName: shipping.recipientName,
      recipientPhone: shipping.phone,
      sellerCode: widget.sellerCode.trim(),
    );
  }

  Future<void> _returnToCartAfterPaymentFailure(String message) async {
    await _releaseReservedCart();
    if (!mounted) return;
    await CatalogScope.of(context).load();
    if (!mounted) return;
    Navigator.of(context).pop();
    if (!mounted) return;
    Navigator.of(context).pop();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _confirmPayment() async {
    if (_isConfirmingPayment) return;
    if (!_isTermsAccepted) return;

    setState(() {
      _validationMessage = null;
      _isConfirmingPayment = true;
    });

    PaymentLoadingOverlay.show(
      context,
      message: tr(PaymentStringKeys.loadingSkladCheck),
    );

    var cartReserved = false;

    try {
      final skladOk = await _verifySkladAndReserveCart();
      if (!mounted) return;

      if (!skladOk) {
        Navigator.of(context).pop();
        setState(() => _isConfirmingPayment = false);
        await _showRetailSoldDialog();
        return;
      }
      cartReserved = true;

      PaymentLoadingOverlay.show(
        context,
        message: tr(PaymentStringKeys.loadingToss),
      );

      final total = widget.productsTotalKrw + widget.deliveryFeeKrw;

      final orderId = await paymentService.createOrderDraft(
        amount: total,
        shippingAddress: widget.shippingAddress.toJson(),
      );

      final initialized = await paymentService.initializeTossPayment(
        orderId: orderId,
        amount: total,
      );

      if (!mounted) return;
      Navigator.of(context).pop();

      if (!initialized) {
        if (cartReserved) {
          await _returnToCartAfterPaymentFailure(
            tr(PaymentStringKeys.paymentFailed),
          );
        }
        setState(() => _isConfirmingPayment = false);
        return;
      }

      setState(() => _isConfirmingPayment = false);

      final launchConfig = paymentService.lastTossLaunchConfig!;
      final webViewResult = await Navigator.of(context).push<TossPaymentWebViewResult>(
        MaterialPageRoute<TossPaymentWebViewResult>(
          builder: (_) => TossWebViewPage(
            clientKey: launchConfig.clientKey,
            orderId: launchConfig.orderId,
            amount: launchConfig.amount,
            successUrl: launchConfig.successUrl,
            failUrl: launchConfig.failUrl,
          ),
        ),
      );

      if (!mounted) return;

      switch (webViewResult) {
        case TossPaymentWebViewResult.success:
          final database = CatalogScope.of(context).database;
          for (final item in _checkoutLineItems) {
            await database.confirmProductPaid(item.product.id);
          }
          if (!mounted) return;
          final cart = CartScope.of(context);
          final purchased = List<CartItem>.from(_checkoutLineItems);

          final paidOrder = _buildPaidOrderItem(
            orderId: orderId,
            totalAmountKrw: total,
            purchased: purchased,
          );
          ProfileScope.of(context).addOrder(paidOrder);

          await retailNotificationService.sendTelegramOrderNotification(
            orderId: orderId,
            cartItems: purchased,
            totalAmountKrw: total,
          );

          for (final item in purchased) {
            cart.removeItem(item.cartKey);
          }
          if (!mounted) return;
          Navigator.of(context).pushReplacement(
            MaterialPageRoute<void>(
              builder: (_) => PaymentSuccessScreen(
                status: OrderPaymentStatus.paid,
                orderId: orderId,
                skipOrderPersistence: true,
              ),
            ),
          );
        case TossPaymentWebViewResult.failed:
          await _returnToCartAfterPaymentFailure(
            tr(PaymentStringKeys.paymentFailed),
          );
        case TossPaymentWebViewResult.cancelled:
        case null:
          await _returnToCartAfterPaymentFailure(
            tr(PaymentStringKeys.paymentCancelled),
          );
      }
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context).pop();
      if (cartReserved) {
        await _returnToCartAfterPaymentFailure(
          tr(PaymentStringKeys.paymentFailed),
        );
      }
      setState(() {
        _isConfirmingPayment = false;
        if (!cartReserved) {
          _validationMessage = tr(PaymentStringKeys.paymentFailed);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: Text(
          tr(PaymentStringKeys.title),
          style: AppTypography.heading(fontSize: 22),
        ),
      ),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.bannerDark],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accent.withValues(alpha: 0.2),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Text(
                        _totalLabel,
                        textAlign: TextAlign.center,
                        style: AppTypography.heading(
                          fontSize: 20,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Способ оплаты выбирается на следующем шаге в защищённом окне Toss Payments (карта, KakaoPay, перевод и др.).',
                      textAlign: TextAlign.center,
                      style: AppTypography.productMeta().copyWith(
                        fontSize: 14,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _MerchantLegalDisclosure(
                maxHeight: MediaQuery.sizeOf(context).height * 0.38,
              ),
            ),
            _PaymentBottomBar(
              validationMessage: _validationMessage,
              onConfirm: _confirmPayment,
              bottomInset: bottomInset,
              label: 'Оплатить через Toss Payments',
              isBusy: _isConfirmingPayment,
              isTermsAccepted: _isTermsAccepted,
              onTermsAcceptedChanged: (value) {
                setState(() => _isTermsAccepted = value ?? false);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Корейский юридический блок (Toss) — над кнопкой оплаты.
class _MerchantLegalDisclosure extends StatelessWidget {
  const _MerchantLegalDisclosure({required this.maxHeight});

  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bodyStyle = theme.textTheme.bodySmall?.copyWith(
          color: AppColors.textSecondary,
          height: 1.45,
        ) ??
        AppTypography.productMeta().copyWith(fontSize: 12, height: 1.45);
    final titleStyle = theme.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ) ??
        AppTypography.caption(fontWeight: FontWeight.w700).copyWith(fontSize: 14);

    return Material(
      color: AppColors.cardBackground,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ExpansionTile(
                initiallyExpanded: true,
                tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                title: Text(
                  MerchantLegalInfo.businessInfoExpansionTitleKo,
                  style: titleStyle,
                ),
                children: [
                  Text(
                    MerchantLegalInfo.businessInfoBodyKo,
                    style: bodyStyle,
                  ),
                ],
              ),
              const Divider(height: 1, color: AppColors.border),
              ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                title: Text(
                  MerchantLegalInfo.refundPolicyExpansionTitleKo,
                  style: titleStyle,
                ),
                children: [
                  Text(
                    MerchantLegalInfo.refundPolicyKo,
                    style: bodyStyle,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PaymentBottomBar extends StatelessWidget {
  const _PaymentBottomBar({
    required this.validationMessage,
    required this.onConfirm,
    required this.bottomInset,
    required this.label,
    required this.isTermsAccepted,
    required this.onTermsAcceptedChanged,
    this.isBusy = false,
  });

  final String? validationMessage;
  final VoidCallback onConfirm;
  final double bottomInset;
  final String label;
  final bool isBusy;
  final bool isTermsAccepted;
  final ValueChanged<bool?> onTermsAcceptedChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottomInset),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CheckboxListTile(
            value: isTermsAccepted,
            onChanged: onTermsAcceptedChanged,
            activeColor: AppColors.primary,
            checkColor: AppColors.textOnPrimary,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(
              MerchantLegalInfo.paymentTermsCheckboxLabelKo,
              style: theme.textTheme.bodyMedium?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ) ??
                  AppTypography.productMeta().copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
          const SizedBox(height: 8),
          if (validationMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.saleRed.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.saleRed.withValues(alpha: 0.25),
                ),
              ),
              child: Text(
                validationMessage!,
                style: AppTypography.caption(color: AppColors.saleRed)
                    .copyWith(fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            height: 50,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.bannerDark],
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.accent.withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: isBusy || !isTermsAccepted ? null : onConfirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  foregroundColor: AppColors.accent,
                  shadowColor: Colors.transparent,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  label,
                  style: AppTypography.caption(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w700,
                  ).copyWith(fontSize: 16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
