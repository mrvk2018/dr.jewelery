import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/services/database_service.dart';
import '../../../shared/models/product_item.dart';
import '../data/local_cart_service.dart';
import '../../payment/domain/models/toss_payment_request.dart';
import '../domain/models/cart_checkout_validation.dart';
import '../domain/models/cart_item.dart';

/// Глобальное состояние корзины с автосохранением на устройстве.
class CartController extends ChangeNotifier {
  static const bonusCheckoutMaxFraction = 0.15;

  static const _blockedCatalogStatuses = {'sold', 'reserved', 'hidden'};

  CartController(
    this._database, {
    required LocalCartService localCart,
    this.availableBonuses = 0,
  }) : _localCart = localCart;

  final DatabaseService _database;
  final LocalCartService _localCart;
  final List<CartItem> _items = [];

  String promoCode = '';
  bool useBonuses = false;
  int availableBonuses;

  List<CartItem> get cartItems => List.unmodifiable(_items);

  /// Совместимость с существующим UI.
  List<CartItem> get items => cartItems;

  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  int get totalOriginalPrice =>
      _items.fold(0, (sum, item) => sum + item.lineOriginalTotal);

  int get totalFinalPrice =>
      _items.fold(0, (sum, item) => sum + item.lineTotal);

  int totalFinalPriceFor(Iterable<CartItem> items) => saleSubtotalFor(items);

  int get subtotal => totalOriginalPrice;

  int get saleSubtotal => totalFinalPrice;

  int get discountTotal => subtotal - saleSubtotal;

  int get promoDiscount => promoDiscountForSubtotal(saleSubtotal);

  int get maxBonusDeduction =>
      (saleSubtotal * bonusCheckoutMaxFraction).round();

  int get bonusDeduction => bonusDeductionForSubtotal(saleSubtotal);

  int get total => checkoutTotalFor(_items);

  bool get hasUnavailableItems => _items.any((item) => item.isUnavailable);

  int saleSubtotalFor(Iterable<CartItem> items) =>
      items.fold(0, (sum, item) => sum + item.lineTotal);

  int promoDiscountForSubtotal(int saleSubtotal) {
    final code = promoCode.trim().toUpperCase();
    if (code.isEmpty) return 0;
    if (code == 'DRJEWELRY' || code == 'VIP') {
      return (saleSubtotal * 0.05).round();
    }
    return 0;
  }

  int bonusDeductionForSubtotal(int saleSubtotal) {
    if (!useBonuses) return 0;
    final cap = (saleSubtotal * bonusCheckoutMaxFraction).round();
    final maxDeduct = availableBonuses < cap ? availableBonuses : cap;
    return maxDeduct;
  }

  int checkoutTotalFor(Iterable<CartItem> items) {
    final list = items.toList();
    if (list.isEmpty) return 0;
    final sale = saleSubtotalFor(list);
    final promo = promoDiscountForSubtotal(sale);
    final bonus = bonusDeductionForSubtotal(sale);
    final result = sale - promo - bonus;
    return result < 0 ? 0 : result;
  }

  Future<void> load() async {
    final snapshot = await _localCart.loadSnapshot();
    if (snapshot == null) {
      final legacy = await _database.loadCartSnapshot();
      if (legacy != null) {
        await _hydrateFromLegacySnapshot(legacy);
        return;
      }
      return;
    }

    _items
      ..clear()
      ..addAll(
        snapshot.items
            .where((item) => item.product != null && item.product!.stockQuantity > 0)
            .map(_clampToStock),
      );
    promoCode = snapshot.promoCode;
    useBonuses = snapshot.useBonuses;
    final authUserId = await _database.currentAuthUserId();
    if (authUserId != null) {
      availableBonuses = await _database.fetchBonusBalanceForCurrentUser();
    } else {
      availableBonuses = snapshot.availableBonuses;
    }
    notifyListeners();
  }

  Future<void> _hydrateFromLegacySnapshot(Map<String, dynamic> legacy) async {
    final rawItems = legacy['items'];
    _items
      ..clear()
      ..addAll(
        (rawItems is List ? rawItems : const [])
            .whereType<Map>()
            .map((item) => CartItem.fromLegacyJson(Map<String, dynamic>.from(item)))
            .where((item) => item.product != null && item.product!.stockQuantity > 0)
            .map(_clampToStock),
      );
    promoCode = legacy['promoCode'] as String? ?? '';
    useBonuses = legacy['useBonuses'] as bool? ?? false;
    final authUserId = await _database.currentAuthUserId();
    if (authUserId != null) {
      availableBonuses = await _database.fetchBonusBalanceForCurrentUser();
    } else {
      availableBonuses = legacy['availableBonuses'] as int? ?? availableBonuses;
    }
    notifyListeners();
    await _persist();
  }

  void addToCart(ProductItem product, String size) {
    if (product.stockQuantity <= 0) return;
    final sizeToken = CartItem.normalizeSize(size);
    final id = CartItem.composeId(sku: product.sku, selectedSize: sizeToken);
    final existing = _items.where((item) => item.id == id).firstOrNull;
    if (existing != null) {
      if (existing.quantity >= product.stockQuantity) return;
      existing.quantity++;
      existing.product = product;
      existing.isUnavailable = false;
    } else {
      _items.add(
        CartItem.fromProduct(
          product: product,
          selectedSize: sizeToken,
        ),
      );
    }
    _notifyAndPersist();
  }

  void addProduct({
    required ProductItem product,
    double? selectedSize,
  }) {
    addToCart(product, selectedSize?.toString() ?? '');
  }

  void removeFromCart(String cartItemId) {
    _items.removeWhere((item) => item.id == cartItemId);
    _notifyAndPersist();
  }

  void removeItem(String cartKey) => removeFromCart(cartKey);

  void incrementQuantity(String cartItemId) {
    final item = _items.where((entry) => entry.id == cartItemId).firstOrNull;
    if (item == null || item.product == null) return;
    if (item.quantity >= item.product!.stockQuantity) return;
    item.quantity++;
    _notifyAndPersist();
  }

  void decrementQuantity(String cartItemId) {
    final item = _items.where((entry) => entry.id == cartItemId).firstOrNull;
    if (item == null) return;
    if (item.quantity <= 1) {
      removeFromCart(cartItemId);
      return;
    }
    item.quantity--;
    _notifyAndPersist();
  }

  CartItem _clampToStock(CartItem item) {
    final product = item.product;
    if (product == null) return item;
    final maxQty = product.stockQuantity;
    if (item.quantity > maxQty) {
      item.quantity = maxQty;
    }
    if (item.quantity < 1) {
      item.quantity = 1;
    }
    return item;
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

  Future<void> syncBonusBalanceFromProfile() async {
    final authUserId = await _database.currentAuthUserId();
    if (authUserId == null) {
      availableBonuses = 0;
      useBonuses = false;
    } else {
      availableBonuses = await _database.fetchBonusBalanceForCurrentUser();
    }
    notifyListeners();
    await _persist();
  }

  void clearCart() {
    _items.clear();
    promoCode = '';
    useBonuses = false;
    _notifyAndPersist();
  }

  void clear() => clearCart();

  /// Проверка всей корзины перед оплатой.
  Future<CartCheckoutValidation> validateCartBeforeCheckout() =>
      validateCheckoutLines(_items);

  /// Проверка выбранных позиций checkout / buy-now по Supabase.
  Future<CartCheckoutValidation> validateCheckoutLines(
    Iterable<CartItem> lines,
  ) async {
    final scoped = lines.toList();
    if (scoped.isEmpty) {
      return const CartCheckoutValidation(
        canProceedToPayment: false,
        unavailableItemIds: [],
      );
    }

    for (final item in scoped) {
      item.isUnavailable = false;
    }

    final productIds = scoped
        .map((item) => item.productId)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (productIds.isEmpty) {
      return const CartCheckoutValidation(
        canProceedToPayment: false,
        unavailableItemIds: [],
      );
    }

    final liveProducts =
        await _database.getProductsByIds(productIds, activeOnly: false);
    final liveById = {for (final product in liveProducts) product.id: product};

    final unavailableIds = <String>[];

    for (final item in scoped) {
      final live = liveById[item.productId];
      if (live == null) {
        item.isUnavailable = true;
        unavailableIds.add(item.id);
        _mirrorLineStateToCart(item);
        continue;
      }

      item.product = live;
      final status = live.catalogStatus.trim().toLowerCase();
      if (_blockedCatalogStatuses.contains(status)) {
        item.isUnavailable = true;
        unavailableIds.add(item.id);
      } else if (!live.isCatalogPurchasable) {
        item.isUnavailable = true;
        unavailableIds.add(item.id);
      }
      _mirrorLineStateToCart(item);
    }

    notifyListeners();
    await _persist();

    return CartCheckoutValidation(
      canProceedToPayment: unavailableIds.isEmpty,
      unavailableItemIds: unavailableIds,
    );
  }

  void _mirrorLineStateToCart(CartItem line) {
    final index = _items.indexWhere((entry) => entry.id == line.id);
    if (index < 0) return;
    _items[index].isUnavailable = line.isUnavailable;
    _items[index].product = line.product;
  }

  /// Сборка Toss payload по валидным строкам корзины.
  TossPaymentRequest buildTossPaymentRequest({
    required Iterable<CartItem> items,
    required String customerName,
    required String customerEmail,
    String? userId,
    String languageCode = 'ko',
    int? amountKrw,
  }) {
    final validLines =
        items.where((item) => !item.isUnavailable && item.product != null).toList();
    final amount = amountKrw ?? totalFinalPriceFor(validLines);

    return TossPaymentRequest(
      orderId: TossPaymentRequest.generateOrderId(userId: userId),
      orderName: TossPaymentRequest.buildOrderName(
        items: validLines,
        languageCode: languageCode,
      ),
      amount: amount,
      customerName: customerName.trim(),
      customerEmail: customerEmail.trim(),
      lineItems: validLines,
    );
  }

  void _notifyAndPersist() {
    notifyListeners();
    unawaited(_persist());
  }

  Future<void> _persist() {
    return _localCart.saveSnapshot(
      CartLocalSnapshot(
        items: List<CartItem>.from(_items),
        promoCode: promoCode,
        useBonuses: useBonuses,
        availableBonuses: availableBonuses,
      ),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    return iterator.current;
  }
}
