/// Корейские правила доставки POS: порог 100 000 ₩.
class SellerPosPricing {
  const SellerPosPricing({
    required this.discountedPriceKrw,
    required this.deliveryFeeKrw,
    required this.totalKrw,
  });

  static const freeDeliveryThresholdKrw = 100000;
  static const standardDeliveryFeeKrw = 5000;

  static const discountOptions = [0, 3, 7, 10, 15, 20];

  final int discountedPriceKrw;
  final int deliveryFeeKrw;
  final int totalKrw;

  factory SellerPosPricing.quote({
    required int basePriceKrw,
    required int discountPercent,
  }) {
    final clamped = discountPercent.clamp(0, 100);
    final discounted =
        (basePriceKrw * (100 - clamped) / 100).round().clamp(0, basePriceKrw);
    final delivery = discounted >= freeDeliveryThresholdKrw
        ? 0
        : standardDeliveryFeeKrw;
    return SellerPosPricing(
      discountedPriceKrw: discounted,
      deliveryFeeKrw: delivery,
      totalKrw: discounted + delivery,
    );
  }
}
