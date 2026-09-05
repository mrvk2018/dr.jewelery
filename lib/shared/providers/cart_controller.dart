import 'package:flutter/foundation.dart';

import '../models/product_item.dart';

/// Позиция в корзине с выбранным размером.
class CartItem {
  CartItem({
    required this.product,
    this.selectedSize,
    this.quantity = 1,
  });

  final ProductItem product;
  final double? selectedSize;
  int quantity;

  int get lineTotal => product.salePrice * quantity;

  int get lineDiscount => (product.oldPrice - product.salePrice) * quantity;

  String get cartKey =>
      '${product.id}_${selectedSize?.toString() ?? 'no_size'}';
}

/// Глобальное состояние корзины приложения.
class CartController extends ChangeNotifier {
  CartController({this.availableBonuses = 4250});

  final List<CartItem> _items = [];
  String promoCode = '';
  bool useBonuses = false;
  int availableBonuses;

  List<CartItem> get items => List.unmodifiable(_items);

  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  int get subtotal =>
      _items.fold(0, (sum, item) => sum + item.product.oldPrice * item.quantity);

  int get saleSubtotal => _items.fold(0, (sum, item) => sum + item.lineTotal);

  int get discountTotal => subtotal - saleSubtotal;

  int get promoDiscount {
    final code = promoCode.trim().toUpperCase();
    if (code.isEmpty) return 0;
    if (code == 'SUNLIGHT' || code == 'VIP') {
      return (saleSubtotal * 0.05).round();
    }
    return 0;
  }

  int get maxBonusDeduction => (saleSubtotal * 0.3).round();

  int get bonusDeduction {
    if (!useBonuses) return 0;
    return availableBonuses < maxBonusDeduction
        ? availableBonuses
        : maxBonusDeduction;
  }

  int get total {
    final result = saleSubtotal - promoDiscount - bonusDeduction;
    return result < 0 ? 0 : result;
  }

  void addProduct({
    required ProductItem product,
    double? selectedSize,
  }) {
    final key = '${product.id}_${selectedSize?.toString() ?? 'no_size'}';
    final existing = _items.where((item) => item.cartKey == key).firstOrNull;
    if (existing != null) {
      existing.quantity++;
    } else {
      _items.add(
        CartItem(product: product, selectedSize: selectedSize),
      );
    }
    notifyListeners();
  }

  void removeItem(String cartKey) {
    _items.removeWhere((item) => item.cartKey == cartKey);
    notifyListeners();
  }

  void setPromoCode(String value) {
    promoCode = value;
    notifyListeners();
  }

  void setUseBonuses(bool value) {
    useBonuses = value;
    notifyListeners();
  }

  void setAvailableBonuses(int value) {
    availableBonuses = value;
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    return iterator.current;
  }
}
