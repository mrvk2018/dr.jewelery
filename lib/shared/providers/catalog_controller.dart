import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/services/database_service.dart';
import '../../features/profile/domain/models/user_profile.dart';
import '../models/product_item.dart';

/// Глобальное состояние каталога: память + постоянное хранилище.
class CatalogController extends ChangeNotifier {
  CatalogController(this._database);

  final DatabaseService _database;
  DatabaseService get database => _database;
  final List<ProductItem> _products = [];
  bool _isLoading = false;
  String? _homeStoryFilterKey;

  List<ProductItem> get products => List.unmodifiable(_products);

  /// Витрина главной с учётом быстрого фильтра «Истории».
  List<ProductItem> get recommendedProducts {
    final filtered = _applyHomeStoryFilter(_products);
    return List.unmodifiable(filtered);
  }

  String? get homeStoryFilterKey => _homeStoryFilterKey;

  bool get isLoading => _isLoading;

  /// Повторное нажатие на активный фильтр сбрасывает его («Все» = null).
  void toggleHomeStoryFilter(String filterKey) {
    if (filterKey == 'all') {
      _homeStoryFilterKey = null;
      notifyListeners();
      return;
    }
    if (_homeStoryFilterKey == filterKey) {
      _homeStoryFilterKey = null;
    } else {
      _homeStoryFilterKey = filterKey;
    }
    notifyListeners();
  }

  List<ProductItem> _applyHomeStoryFilter(List<ProductItem> source) {
    final key = _homeStoryFilterKey;
    if (key == null) {
      return List<ProductItem>.from(source);
    }
    if (key == 'new') {
      final sorted = List<ProductItem>.from(source);
      sorted.sort((a, b) => b.id.compareTo(a.id));
      return sorted;
    }
    return source.where((product) => _matchesHomeStoryFilter(product, key)).toList();
  }

  bool _matchesHomeStoryFilter(ProductItem product, String filterKey) {
    switch (filterKey) {
      case 'discounts':
        return product.discountPercent > 0;
      case 'rings':
        return _categoryMatches(product.category, const ['Кольцо', 'Кольца']);
      case 'earrings':
        return _categoryMatches(product.category, const ['Серьги']);
      case 'chains':
        return _categoryMatches(product.category, const ['Цепь', 'Цепи']);
      case 'gold':
        return _metalContains(product.metal, const ['золото', 'gold']);
      case 'silver':
        return _metalContains(product.metal, const ['серебро', 'silver']);
      case 'gifts':
        return _categoryMatches(product.category, const ['Подарки', 'Подарок']) ||
            product.localizedName('ru').toLowerCase().contains('подар');
      default:
        return true;
    }
  }

  bool _categoryMatches(String category, List<String> variants) {
    final normalized = category.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    for (final variant in variants) {
      final v = variant.toLowerCase();
      if (normalized == v || normalized.contains(v)) return true;
    }
    return false;
  }

  bool _metalContains(String metal, List<String> needles) {
    final normalized = metal.trim().toLowerCase();
    if (normalized.isEmpty) return false;
    return needles.any(normalized.contains);
  }

  /// Асинхронная загрузка витрины. Пустая база засевается демо-товарами.
  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    try {
      final loaded = await _database.getProducts();
      _products
        ..clear()
        ..addAll(loaded);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void addProduct(
    ProductItem item, {
    UserRole actorRole = UserRole.admin,
  }) {
    _products.insert(0, item);
    notifyListeners();
    unawaited(_database.saveProduct(item, actorRole));
  }

  void removeProduct(
    String id, {
    UserRole actorRole = UserRole.admin,
  }) {
    final before = _products.length;
    _products.removeWhere((product) => product.id == id);
    if (_products.length == before) return;
    notifyListeners();
    unawaited(_database.deleteProduct(id, actorRole));
  }

  /// Обновление остатка с кассы (POS) по артикулу SKU.
  Future<void> updateProductStock(String sku, int newQuantity) async {
    await _database.updateProductStock(sku, newQuantity);
    final index = _products.indexWhere((product) => product.sku == sku);
    if (index < 0) return;
    final quantity = newQuantity < 0 ? 0 : newQuantity;
    _products[index] = _products[index].copyWith(stockQuantity: quantity);
    notifyListeners();
  }
}
