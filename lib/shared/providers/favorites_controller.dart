import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/services/database_service.dart';
import '../models/product_item.dart';

/// Глобальное избранное: ID товаров + автосохранение в `dj_favorites_v1`.
class FavoritesController extends ChangeNotifier {
  FavoritesController(this._database);

  final DatabaseService _database;
  final Set<String> _ids = <String>{};
  bool _isLoading = false;

  List<String> get ids => List.unmodifiable(_ids);

  bool get isLoading => _isLoading;

  bool get isEmpty => _ids.isEmpty;

  bool isFavorite(ProductItem item) => _ids.contains(item.id);

  bool containsId(String id) => _ids.contains(id);

  List<ProductItem> resolveProducts(List<ProductItem> catalog) {
    return catalog.where((product) => _ids.contains(product.id)).toList();
  }

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    try {
      final loaded = await _database.loadFavoriteIds();
      _ids
        ..clear()
        ..addAll(loaded);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void toggleFavorite(ProductItem item) {
    if (_ids.contains(item.id)) {
      _ids.remove(item.id);
    } else {
      _ids.add(item.id);
    }
    notifyListeners();
    unawaited(_persist());
  }

  Future<void> _persist() {
    return _database.saveFavoriteIds(_ids.toList());
  }
}
