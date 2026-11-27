import 'package:flutter/foundation.dart';

import '../../../shared/models/product_item.dart';
import '../domain/models/pos_cart_item.dart';
import '../domain/pos_cart_gold_utils.dart';
import '../domain/trade_in_scrap_draft.dart';

class PosCartController extends ChangeNotifier {
  final List<PosCartItem> _items = [];
  TradeInScrapDraft? _tradeInDraft;
  bool _applyingRemote = false;

  List<PosCartItem> get items => List.unmodifiable(_items);
  bool get isApplyingRemote => _applyingRemote;
  TradeInScrapDraft? get tradeInDraft => _tradeInDraft;

  int get lineCount => _items.length;

  int get totalFinalKrw =>
      _items.fold(0, (sum, line) => sum + line.finalPriceKrw);

  bool containsProduct(String productId) =>
      _items.any((line) => line.product.id == productId);

  void addToCart(ProductItem product, {int discountPercent = 0}) {
    if (_applyingRemote) return;
    if (!product.isCatalogPurchasable || product.isOutOfStock) return;
    if (containsProduct(product.id)) return;
    _items.add(
      PosCartItem(product: product, discountPercent: discountPercent),
    );
    notifyListeners();
  }

  void removeFromCart(String productId) {
    if (_applyingRemote) return;
    _items.removeWhere((line) => line.product.id == productId);
    notifyListeners();
  }

  double get cartGoldWeightGrams => sumPosCartGoldWeightGrams(_items);

  bool get hasGoldInCart => countPosCartGoldLines(_items) > 0;

  bool get tradeInGoldWeightStale {
    final draft = _tradeInDraft;
    if (draft == null) return false;
  final current = cartGoldWeightGrams;
    return (current - draft.cartGoldWeightGrams).abs() > 0.0001;
  }

  void attachTradeInDraft(TradeInScrapDraft draft) {
    _tradeInDraft = draft;
    notifyListeners();
  }

  void clearTradeInDraft() {
    if (_tradeInDraft == null) return;
    _tradeInDraft = null;
    notifyListeners();
  }

  /// Сброс Trade-In при закрытии POS-корзины (сессия модалки).
  void clearTradeInSession() => clearTradeInDraft();

  void setLineDiscount(String productId, int discountPercent) {
    if (_applyingRemote) return;
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
    if (_applyingRemote) return;
    if (_items.isEmpty && _tradeInDraft == null) return;
    _items.clear();
    _tradeInDraft = null;
    notifyListeners();
  }

  void replaceFromRemote(List<PosCartItem> lines) {
    _applyingRemote = true;
  try {
      _items
        ..clear()
        ..addAll(lines);
    } finally {
      _applyingRemote = false;
    }
    notifyListeners();
  }

  List<Map<String, dynamic>> toSaleLineInputs() =>
      _items.map((line) => line.toSaleLineInput()).toList();
}
