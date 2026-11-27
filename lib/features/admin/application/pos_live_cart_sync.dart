import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/database_service.dart';
import '../../../shared/models/product_item.dart';
import '../domain/models/pos_cart_item.dart';
import 'pos_cart_controller.dart';

/// Синхронизация POS-корзины с `pos_user_cart_items` + Realtime по `auth.uid()`.
class PosLiveCartSync {
  PosLiveCartSync({
    required this.cart,
    required this.database,
  });

  final PosCartController cart;
  final DatabaseService database;

  RealtimeChannel? _channel;
  bool _started = false;
  bool _hydrating = false;

  String? get _userId => Supabase.instance.client.auth.currentUser?.id;

  Future<void> start() async {
    if (_started || _userId == null) return;
    _started = true;
    await _pullRemoteIntoCart();
    _subscribe();
    cart.addListener(_onLocalCartChanged);
  }

  void dispose() {
    cart.removeListener(_onLocalCartChanged);
    final ch = _channel;
    if (ch != null) {
      unawaited(ch.unsubscribe());
    }
    _channel = null;
    _started = false;
  }

  void _subscribe() {
    final uid = _userId;
    if (uid == null) return;
    try {
      _channel = Supabase.instance.client
          .channel('pos_user_cart_$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'pos_user_cart_items',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: uid,
            ),
            callback: (_) {
              unawaited(_pullRemoteIntoCart());
            },
          )
          .subscribe();
    } catch (error, stackTrace) {
      debugPrint('PosLiveCartSync._subscribe: $error');
      debugPrint('$stackTrace');
    }
  }

  Future<void> _pullRemoteIntoCart() async {
    if (_hydrating || cart.isApplyingRemote) return;
    _hydrating = true;
    try {
      final remoteLines = await database.listPosUserCartItems();
      final built = <PosCartItem>[];
      for (final line in remoteLines) {
        final productId = line['product_id']?.toString();
        if (productId == null || productId.isEmpty) continue;
        final row = await database.fetchProductRowForPosLookup(productId);
        if (row == null) continue;
        final product = ProductItem.fromJson(
          CloudDatabaseService.productRowToClientJson(row),
        );
        final discount =
            (line['discount_percent'] as num?)?.toInt() ?? 0;
        built.add(PosCartItem(product: product, discountPercent: discount));
      }
      cart.replaceFromRemote(built);
    } catch (error, stackTrace) {
      debugPrint('PosLiveCartSync._pullRemoteIntoCart: $error');
      debugPrint('$stackTrace');
    } finally {
      _hydrating = false;
    }
  }

  void _onLocalCartChanged() {
    if (cart.isApplyingRemote || _hydrating || _userId == null) return;
    unawaited(_pushLocalToRemote());
  }

  Future<void> _pushLocalToRemote() async {
    final uid = _userId;
    if (uid == null) return;
    try {
      final remote = await database.listPosUserCartItems();
      final localIds =
          cart.items.map((line) => line.product.id).toSet();
      final remoteIds = remote
          .map((r) => r['product_id']?.toString())
          .whereType<String>()
          .toSet();

      for (final removed in remoteIds.difference(localIds)) {
        await database.removePosUserCartItem(removed);
      }

      for (var index = 0; index < cart.items.length; index++) {
        final line = cart.items[index];
        await database.upsertPosUserCartItem(
          productId: line.product.id,
          discountPercent: line.discountPercent,
          sortOrder: index,
        );
      }
    } catch (error, stackTrace) {
      debugPrint('PosLiveCartSync._pushLocalToRemote: $error');
      debugPrint('$stackTrace');
    }
  }

  Future<void> clearRemote() => database.clearPosUserCartRemote();
}