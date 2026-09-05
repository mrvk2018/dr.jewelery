import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/services/database_service.dart';
import '../../features/profile/domain/models/user_profile.dart';
import '../models/product_item.dart';

/// Глобальное состояние каталога: память + постоянное хранилище.
class CatalogController extends ChangeNotifier {
  CatalogController(this._database);

  final DatabaseService _database;
  final List<ProductItem> _products = [];
  bool _isLoading = false;

  List<ProductItem> get products => List.unmodifiable(_products);

  bool get isLoading => _isLoading;

  /// Асинхронная загрузка витрины. Пустая база засевается демо-товарами.
  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    try {
      final loaded = await _database.loadProducts();
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
    unawaited(_database.saveProduct(item, actorRole: actorRole));
  }

  void removeProduct(
    String id, {
    UserRole actorRole = UserRole.admin,
  }) {
    final before = _products.length;
    _products.removeWhere((product) => product.id == id);
    if (_products.length == before) return;
    notifyListeners();
    unawaited(_database.deleteProduct(id, actorRole: actorRole));
  }
}
