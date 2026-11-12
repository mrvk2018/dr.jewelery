import 'package:flutter/foundation.dart';

import '../../../shared/models/product_item.dart';
import '../domain/models/pos_cart_item.dart';

class PosCartController extends ChangeNotifier {
  final List<PosCartItem> _items = [];

  List<PosCartItem> get items => List.unmodifiable(_items);

  int get lineCount => _items.length;

  int get totalFinalKrw =>
      _items.fold(0, (sum, line) => sum + line.finalPriceKrw);

  bool containsProduct(String productId) =>
      _items.any((line) => line.product.id == productId);

  void addToCart(ProductItem product) {
    if (!product.isCatalogPurchasable || product.isOutOfStock) return;
    if (containsProduct(product.id)) return;
    _items.add(PosCartItem(product: product));
    notifyListeners();
  }

  void removeFromCart(String productId) {
    _items.removeWhere((line) => line.product.id == productId);
    notifyListeners();
  }

  void setLineDiscount(String productId, int discountPercent) {
    if (!PosCartDiscountOptions.values.contains(discountPercent)) return;
    for (final line in _items) {
      if (line.product.id == productId) {
        line.discountPercent = discountPercent;
        break;
      }
    }
    notifyListeners();
  }

  void clearCart() {
    if (_items.isEmpty) return;
    _items.clear();
    notifyListeners();
  }

  List<Map<String, dynamic>> toSaleLineInputs() =>
      _items.map((line) => line.toSaleLineInput()).toList();
}
