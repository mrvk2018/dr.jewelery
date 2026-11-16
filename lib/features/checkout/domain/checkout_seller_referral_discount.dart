import '../../../core/utils/jewelry_metal_category.dart';
import '../../cart/domain/models/cart_item.dart';

/// Скидка по промокоду продавца с учётом металла позиций (после промо/бонусов корзины).
int sellerReferralDiscountKrw({
  required List<CartItem> items,
  required int saleSubtotal,
  required int promoDiscount,
  required int bonusDeduction,
  required int goldDiscountPercent,
  required int silverDiscountPercent,
}) {
  if (goldDiscountPercent <= 0 && silverDiscountPercent <= 0) return 0;
  if (saleSubtotal <= 0) return 0;

  var discount = 0;
  for (final item in items) {
    if (item.isUnavailable) continue;
    final lineSale = item.lineTotal;
    if (lineSale <= 0) continue;

    final linePromo = saleSubtotal > 0
        ? (lineSale * promoDiscount / saleSubtotal).round()
        : 0;
    final lineBonus = saleSubtotal > 0
        ? (lineSale * bonusDeduction / saleSubtotal).round()
        : 0;
    final lineAfterCart = lineSale - linePromo - lineBonus;
    if (lineAfterCart <= 0) continue;

    final product = item.product;
    final category = classifyJewelryMetalCategory(
      metal: product?.metal,
    );
    final pct = switch (category) {
      JewelryMetalCategory.gold => goldDiscountPercent,
      JewelryMetalCategory.silver => silverDiscountPercent,
      JewelryMetalCategory.other => 0,
    };
    if (pct <= 0) continue;
    discount += (lineAfterCart * pct / 100.0).floor();
  }
  return discount;
}

int sellerReferralPayableProductsTotal({
  required int liveProductsTotal,
  required int referralDiscountKrw,
}) {
  if (referralDiscountKrw <= 0) return liveProductsTotal;
  final intermediateTotal = liveProductsTotal - referralDiscountKrw;
  final finalPayable = ((intermediateTotal + 99) ~/ 100) * 100;
  return finalPayable > liveProductsTotal ? liveProductsTotal : finalPayable;
}