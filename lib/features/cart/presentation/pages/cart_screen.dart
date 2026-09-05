import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../checkout/presentation/pages/checkout_screen.dart';
import '../../../../shared/providers/cart_scope.dart';
import '../widgets/cart_widgets.dart';

/// Экран корзины с расчётом и оформлением заказа.
class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  late final TextEditingController _promoController;

  @override
  void initState() {
    super.initState();
    _promoController = TextEditingController();
  }

  @override
  void dispose() {
    _promoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = CartScope.of(context);

    return AnimatedBuilder(
      animation: cart,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: Text('Корзина', style: AppTypography.heading(fontSize: 24)),
            actions: [
              if (cart.items.isNotEmpty)
                TextButton(
                  onPressed: cart.clear,
                  child: Text(
                    'Очистить',
                    style: AppTypography.caption(color: AppColors.textSecondary),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: cart.items.isEmpty
              ? null
              : CartCheckoutBar(
                  total: cart.total,
                  onCheckout: () {
                    Navigator.of(context).push<void>(
                      MaterialPageRoute<void>(
                        builder: (_) => CheckoutScreen(
                          productsTotal: cart.total,
                        ),
                      ),
                    );
                  },
                ),
          body: cart.items.isEmpty
              ? _EmptyCartView()
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(
                      'Товары (${cart.itemCount})',
                      style: AppTypography.heading(fontSize: 18),
                    ),
                    const SizedBox(height: 12),
                    ...cart.items.map(
                      (item) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: CartItemTile(
                          item: item,
                          onRemove: () => cart.removeItem(item.cartKey),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    CartLoyaltySection(
                      promoController: _promoController,
                      useBonuses: cart.useBonuses,
                      availableBonuses: cart.availableBonuses,
                      bonusDeduction: cart.bonusDeduction,
                      onPromoChanged: cart.setPromoCode,
                      onUseBonusesChanged: cart.setUseBonuses,
                    ),
                    const SizedBox(height: 12),
                    CartSummarySection(
                      subtotal: cart.subtotal,
                      discount: cart.discountTotal,
                      promoDiscount: cart.promoDiscount,
                      bonusDeduction: cart.bonusDeduction,
                      total: cart.total,
                    ),
                    const SizedBox(height: 100),
                  ],
                ),
        );
      },
    );
  }
}

class _EmptyCartView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.shopping_bag_outlined,
              size: 64,
              color: AppColors.textSecondary.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'Корзина пуста',
              style: AppTypography.heading(fontSize: 22),
            ),
            const SizedBox(height: 8),
            Text(
              'Добавьте украшения из каталога или главной страницы',
              textAlign: TextAlign.center,
              style: AppTypography.productMeta().copyWith(fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
