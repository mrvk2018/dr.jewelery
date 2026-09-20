import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../checkout/presentation/pages/checkout_screen.dart';
import '../../../../shared/providers/cart_controller.dart';
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
  bool _promoSynced = false;
  final Map<String, bool> _selectedByCartKey = {};

  @override
  void initState() {
    super.initState();
    _promoController = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_promoSynced) return;
    _promoSynced = true;
    _promoController.text = CartScope.of(context).promoCode;
  }

  @override
  void dispose() {
    _promoController.dispose();
    super.dispose();
  }

  void _syncSelectionWithCart(CartController cart) {
    final keys = cart.items.map((item) => item.cartKey).toSet();
    _selectedByCartKey.removeWhere((key, _) => !keys.contains(key));
    for (final key in keys) {
      _selectedByCartKey.putIfAbsent(key, () => true);
    }
  }

  List<CartItem> _selectedItems(CartController cart) {
    return cart.items
        .where((item) => _selectedByCartKey[item.cartKey] ?? true)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final cart = CartScope.of(context);

    return AnimatedBuilder(
      animation: cart,
      builder: (context, _) {
        _syncSelectionWithCart(cart);
        final selectedItems = _selectedItems(cart);
        final selectedSaleSubtotal = cart.saleSubtotalFor(selectedItems);
        final selectedPromo = cart.promoDiscountForSubtotal(selectedSaleSubtotal);
        final selectedBonus =
            cart.bonusDeductionForSubtotal(selectedSaleSubtotal);
        final selectedTotal = cart.checkoutTotalFor(selectedItems);
        final selectedSubtotal = selectedItems.fold<int>(
          0,
          (sum, item) => sum + item.product.oldPrice * item.quantity,
        );
        final selectedDiscount = selectedSubtotal - selectedSaleSubtotal;

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
                  total: selectedTotal,
                  checkoutEnabled: selectedItems.isNotEmpty,
                  onCheckout: selectedItems.isEmpty
                      ? null
                      : () {
                          Navigator.of(context).push<void>(
                            MaterialPageRoute<void>(
                              builder: (_) => CheckoutScreen(
                                productsTotal: selectedTotal,
                                checkoutItems:
                                    List<CartItem>.from(selectedItems),
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
                          isSelected:
                              _selectedByCartKey[item.cartKey] ?? true,
                          onSelectedChanged: (value) {
                            setState(() {
                              _selectedByCartKey[item.cartKey] =
                                  value ?? false;
                            });
                          },
                          onRemove: () => cart.removeItem(item.cartKey),
                          onIncrement: () =>
                              cart.incrementQuantity(item.cartKey),
                          onDecrement: () =>
                              cart.decrementQuantity(item.cartKey),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    CartLoyaltySection(
                      promoController: _promoController,
                      useBonuses: cart.useBonuses,
                      availableBonuses: cart.availableBonuses,
                      bonusDeduction: selectedBonus,
                      onPromoChanged: cart.setPromoCode,
                      onUseBonusesChanged: cart.setUseBonuses,
                    ),
                    const SizedBox(height: 12),
                    CartSummarySection(
                      subtotal: selectedSubtotal,
                      discount: selectedDiscount,
                      promoDiscount: selectedPromo,
                      bonusDeduction: selectedBonus,
                      total: selectedTotal,
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
