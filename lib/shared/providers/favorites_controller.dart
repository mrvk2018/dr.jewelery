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
  bool _isResolving = false;

  List<String> get ids => List.unmodifiable(_ids);

  bool get isLoading => _isLoading;

  bool get isResolving => _isResolving;

  bool get isEmpty => _ids.isEmpty;

  bool isFavorite(ProductItem item) => _ids.contains(item.id);

  bool containsId(String id) => _ids.contains(id);

  /// Живые карточки с Supabase по id; «мёртвые» id удаляются локально.
  Future<List<ProductItem>> resolveProductsFromServer() async {
    if (_ids.isEmpty) return [];
    _isResolving = true;
    notifyListeners();
    try {
      final fromDb = await _database.getProductsByIds(_ids.toList());
      final liveIds = fromDb.map((p) => p.id).toSet();
      final deadIds = _ids.where((id) => !liveIds.contains(id)).toList();
      if (deadIds.isNotEmpty) {
        for (final id in deadIds) {
          _ids.remove(id);
        }
        await _persist();
      }
      return fromDb;
    } finally {
      _isResolving = false;
      notifyListeners();
    }
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
