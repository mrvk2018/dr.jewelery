import '../../../../shared/models/product_item.dart';

/// Допустимые POS-скидки на строку (согласовано с `pos_sale_line_input`).
abstract final class PosCartDiscountOptions {
  static const List<int> values = [0, 3, 5, 7, 10, 15, 20];
}

class PosCartItem {
  PosCartItem({
    required this.product,
    this.discountPercent = 0,
  }) : assert(PosCartDiscountOptions.values.contains(discountPercent));

  final ProductItem product;
  int discountPercent;

  int get originalPriceKrw => product.salePrice;

  int get finalPriceKrw {
    final discount = discountPercent.clamp(0, 100);
    return (originalPriceKrw * (100 - discount) / 100).round();
  }

  Map<String, dynamic> toSaleLineInput() => {
        'product_id': product.id,
        'discount_percent': discountPercent,
      };
}
