import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/l10n/payment_localizations.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/providers/cart_scope.dart';
import '../../../../shared/providers/profile_scope.dart';
import '../../../profile/domain/models/order_item.dart';
import '../../../shell/presentation/pages/main_screen.dart';
import '../../domain/models/payment_models.dart';

/// Экран успешного оформления заказа с золотой анимацией.
class PaymentSuccessScreen extends StatefulWidget {
  const PaymentSuccessScreen({
    super.key,
    required this.status,
    this.orderId,
  });

  final OrderPaymentStatus status;

  /// Идентификатор заказа с бэкенда / Toss (если уже создан до WebView).
  final String? orderId;

  @override
  State<PaymentSuccessScreen> createState() => _PaymentSuccessScreenState();
}

class _PaymentSuccessScreenState extends State<PaymentSuccessScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  String tr(String key) => paymentTr(key, context.langCode);

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scale = CurvedAnimation(
      parent: _controller,
      curve: Curves.elasticOut,
    );
    _fade = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.3, 1, curve: Curves.easeOut),
    );
    _controller.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _persistPaidOrder();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _persistPaidOrder() {
    final cart = CartScope.of(context);
    if (cart.items.isEmpty) return;

    final profile = ProfileScope.of(context);
    final languageCode = context.langCode;
    final names = cart.items
        .map(
          (item) =>
              item.product.nameTranslations[languageCode] ??
              item.product.nameTranslations['ru'] ??
              '',
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

    profile.addOrder(
      OrderItem(
        id: widget.orderId ?? 'ORD-${now.millisecondsSinceEpoch}',
        productName: names,
        amount: cart.total,
        status: widget.status == OrderPaymentStatus.paid
            ? OrderStatus.paid
            : OrderStatus.newOrder,
        dateLabel: '${now.day} ${months[now.month - 1]} ${now.year}',
        customerName: profile.user.name.isEmpty ? 'Гость' : profile.user.name,
      ),
    );
    cart.clear();
  }

  void _returnHome() {
    if (CartScope.of(context).items.isNotEmpty) {
      _persistPaidOrder();
    }
    Navigator.of(context).pushAndRemoveUntil<void>(
      MaterialPageRoute<void>(builder: (_) => const MainScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final subtitle = widget.status == OrderPaymentStatus.paid
        ? tr(PaymentStringKeys.successSubtitlePaid)
        : tr(PaymentStringKeys.successSubtitleAwaiting);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Spacer(),
              ScaleTransition(
                scale: _scale,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppColors.bannerGoldStart,
                        AppColors.accent,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.accent.withValues(alpha: 0.45),
                        blurRadius: 28,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 64,
                    color: AppColors.textOnAccent,
                  ),
                ),
              ),
              const SizedBox(height: 32),
              FadeTransition(
                opacity: _fade,
                child: Column(
                  children: [
                    Text(
                      tr(PaymentStringKeys.successTitle),
                      textAlign: TextAlign.center,
                      style: AppTypography.heading(fontSize: 26),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      subtitle,
                      textAlign: TextAlign.center,
                      style: AppTypography.productMeta().copyWith(
                        fontSize: 15,
                        height: 1.5,
                      ),
                    ),
                    if (widget.status == OrderPaymentStatus.awaitingPayment) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.cardBackground,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'Hana Bank · $hanaBankAccountNumber',
                              style: AppTypography.caption(
                                fontWeight: FontWeight.w700,
                              ).copyWith(fontSize: 14),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              tr(PaymentStringKeys.recipientName),
                              style: AppTypography.productMeta(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Spacer(flex: 2),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.bannerDark],
                    ),
                  ),
                  child: ElevatedButton(
                    onPressed: _returnHome,
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
                      tr(PaymentStringKeys.backToHome),
                      style: AppTypography.caption(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w700,
                      ).copyWith(fontSize: 16),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
