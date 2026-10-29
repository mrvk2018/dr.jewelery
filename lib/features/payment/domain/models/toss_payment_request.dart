import '../../../../shared/models/product_item.dart';
import '../../../cart/domain/models/cart_item.dart';

/// Payload для инициализации Toss Payments (Widget / Edge confirm).
class TossPaymentRequest {
  const TossPaymentRequest({
    required this.orderId,
    required this.orderName,
    required this.amount,
    required this.customerName,
    required this.customerEmail,
    required this.lineItems,
  });

  final String orderId;
  final String orderName;
  final int amount;
  final String customerName;
  final String customerEmail;
  final List<CartItem> lineItems;

  Map<String, dynamic> toJson() => {
        'orderId': orderId,
        'orderName': orderName,
        'amount': amount,
        'customerName': customerName,
        'customerEmail': customerEmail,
        'lineItems': lineItems.map((item) => item.toJson()).toList(),
      };

  /// `DRJ_{timestamp}_{userId}` — уникальный идентификатор заказа в Toss.
  static String generateOrderId({String? userId}) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final uidPart = userId?.trim().isNotEmpty == true ? userId!.trim() : 'guest';
    return 'DRJ_${timestamp}_$uidPart';
  }

  /// Название заказа для Toss (один SKU vs несколько).
  static String buildOrderName({
    required List<CartItem> items,
    String languageCode = 'ko',
  }) {
    if (items.isEmpty) return 'Dr.Jewelry order';

    final firstProduct = items.first.loadedProduct;
    final primaryName = _primaryProductTitle(firstProduct, languageCode);

    if (items.length == 1) {
      return primaryName;
    }

    final extraCount = items.length - 1;
    return switch (languageCode) {
      'ko' => '$primaryName 외 $extraCount개',
      'en' => '$primaryName and $extraCount more items',
      _ => '$primaryName и ещё $extraCount изделий',
    };
  }

  static String _primaryProductTitle(ProductItem product, String languageCode) {
    final localized = product.localizedName(languageCode).trim();
    if (localized.isNotEmpty) return localized;
    final ru = product.localizedName('ru').trim();
    if (ru.isNotEmpty) return ru;
    return product.sku.isNotEmpty ? product.sku : 'Dr.Jewelry';
  }
}
