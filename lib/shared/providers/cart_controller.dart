import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/services/database_service.dart';
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

  Map<String, dynamic> toJson() => {
        'product': product.toJson(),
        'selectedSize': selectedSize,
        'quantity': quantity,
      };

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      product: ProductItem.fromJson(
        Map<String, dynamic>.from(json['product'] as Map),
      ),
      selectedSize: (json['selectedSize'] as num?)?.toDouble(),
      quantity: json['quantity'] as int? ?? 1,
    );
  }
}

/// Глобальное состояние корзины с автосохранением в локальную базу.
class CartController extends ChangeNotifier {
  CartController(this._database, {this.availableBonuses = 85000});

  final DatabaseService _database;
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
    if (code == 'DRJEWELRY' || code == 'VIP') {
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

  Future<void> load() async {
    final snapshot = await _database.loadCartSnapshot();
    if (snapshot == null) return;

    final rawItems = snapshot['items'];
    _items
      ..clear()
      ..addAll(
        (rawItems is List ? rawItems : const [])
            .whereType<Map>()
            .map((item) => CartItem.fromJson(Map<String, dynamic>.from(item)))
            .where((item) => item.product.stockQuantity > 0)
            .map(_clampToStock),
      );
    promoCode = snapshot['promoCode'] as String? ?? '';
    useBonuses = snapshot['useBonuses'] as bool? ?? false;
    availableBonuses = snapshot['availableBonuses'] as int? ?? availableBonuses;
    notifyListeners();
  }

  void addProduct({
    required ProductItem product,
    double? selectedSize,
  }) {
    if (product.stockQuantity <= 0) return;
    final key = '${product.id}_${selectedSize?.toString() ?? 'no_size'}';
    final existing = _items.where((item) => item.cartKey == key).firstOrNull;
    if (existing != null) {
      if (existing.quantity >= product.stockQuantity) return;
      existing.quantity++;
    } else {
      _items.add(
        CartItem(product: product, selectedSize: selectedSize),
      );
    }
    _notifyAndPersist();
  }

  void incrementQuantity(String cartKey) {
    final item = _items.where((entry) => entry.cartKey == cartKey).firstOrNull;
    if (item == null) return;
    if (item.quantity >= item.product.stockQuantity) return;
    item.quantity++;
    _notifyAndPersist();
  }

  void decrementQuantity(String cartKey) {
    final item = _items.where((entry) => entry.cartKey == cartKey).firstOrNull;
    if (item == null) return;
    if (item.quantity <= 1) {
      removeItem(cartKey);
      return;
    }
    item.quantity--;
    _notifyAndPersist();
  }

  CartItem _clampToStock(CartItem item) {
    final maxQty = item.product.stockQuantity;
    if (item.quantity > maxQty) {
      item.quantity = maxQty;
    }
    if (item.quantity < 1) {
      item.quantity = 1;
    }
    return item;
  }

  void removeItem(String cartKey) {
    _items.removeWhere((item) => item.cartKey == cartKey);
    _notifyAndPersist();
  }

  void setPromoCode(String value) {
    promoCode = value;
    _notifyAndPersist();
  }

  void setUseBonuses(bool value) {
    useBonuses = value;
    _notifyAndPersist();
  }

  void setAvailableBonuses(int value) {
    availableBonuses = value;
    _notifyAndPersist();
  }

  void clear() {
    _items.clear();
    promoCode = '';
    useBonuses = false;
    _notifyAndPersist();
  }

  void _notifyAndPersist() {
    notifyListeners();
    unawaited(_persist());
  }

  Future<void> _persist() {
    return _database.saveCartSnapshot({
      'items': _items.map((item) => item.toJson()).toList(),
      'promoCode': promoCode,
      'useBonuses': useBonuses,
      'availableBonuses': availableBonuses,
    });
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    return iterator.current;
  }
}
