/// Результат проверки корзины перед оплатой.
class CartCheckoutValidation {
  const CartCheckoutValidation({
    required this.canProceedToPayment,
    required this.unavailableItemIds,
  });

  final bool canProceedToPayment;
  final List<String> unavailableItemIds;
}
