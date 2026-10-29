import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/database_service.dart';
import '../domain/models/cart_item.dart';

/// Локальное хранение корзины (SharedPreferences, ключ [DatabaseCollections.cart]).
class LocalCartService {
  LocalCartService(this._prefs);

  static const _schemaVersion = 2;

  final SharedPreferences _prefs;

  static Future<LocalCartService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return LocalCartService(prefs);
  }

  Future<List<CartItem>> loadItems() async {
    final snapshot = await loadSnapshot();
    return snapshot?.items ?? const [];
  }

  Future<CartLocalSnapshot?> loadSnapshot() async {
    final raw = _prefs.getString(DatabaseCollections.cart);
    if (raw == null || raw.isEmpty) return null;

    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final map = Map<String, dynamic>.from(decoded);

    final version = map['schema'] as int? ?? 1;
    final rawItems = map['items'];
    if (rawItems is! List) return null;

    final items = <CartItem>[];
    for (final entry in rawItems) {
      if (entry is! Map) continue;
      final itemMap = Map<String, dynamic>.from(entry);
      try {
        if (version >= 2 && itemMap.containsKey('productId')) {
          items.add(CartItem.fromJson(itemMap));
        } else if (itemMap.containsKey('product')) {
          items.add(CartItem.fromLegacyJson(itemMap));
        }
      } catch (_) {
        continue;
      }
    }

    return CartLocalSnapshot(
      items: items,
      promoCode: map['promoCode'] as String? ?? '',
      useBonuses: map['useBonuses'] as bool? ?? false,
      availableBonuses: map['availableBonuses'] as int? ?? 0,
    );
  }

  Future<void> saveSnapshot(CartLocalSnapshot snapshot) async {
    await _prefs.setString(
      DatabaseCollections.cart,
      jsonEncode({
        'schema': _schemaVersion,
        'items': snapshot.items.map((item) => item.toJson()).toList(),
        'promoCode': snapshot.promoCode,
        'useBonuses': snapshot.useBonuses,
        'availableBonuses': snapshot.availableBonuses,
      }),
    );
  }

  Future<void> saveItems(List<CartItem> items) async {
    final existing = await loadSnapshot();
    await saveSnapshot(
      CartLocalSnapshot(
        items: items,
        promoCode: existing?.promoCode ?? '',
        useBonuses: existing?.useBonuses ?? false,
        availableBonuses: existing?.availableBonuses ?? 0,
      ),
    );
  }

  Future<void> clearItems() async {
    final existing = await loadSnapshot();
    await saveSnapshot(
      CartLocalSnapshot(
        items: const [],
        promoCode: existing?.promoCode ?? '',
        useBonuses: existing?.useBonuses ?? false,
        availableBonuses: existing?.availableBonuses ?? 0,
      ),
    );
  }
}

class CartLocalSnapshot {
  const CartLocalSnapshot({
    required this.items,
    required this.promoCode,
    required this.useBonuses,
    required this.availableBonuses,
  });

  final List<CartItem> items;
  final String promoCode;
  final bool useBonuses;
  final int availableBonuses;
}
