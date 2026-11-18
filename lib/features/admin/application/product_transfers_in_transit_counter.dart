import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/database_service.dart';

/// Счётчик `product_transfers` в статусе `in_transit` (как вкладка «Трансферы» по умолчанию).
class ProductTransfersInTransitCounter extends ChangeNotifier {
  ProductTransfersInTransitCounter(this._database);

  final DatabaseService _database;

  int _count = 0;
  RealtimeChannel? _channel;
  bool _started = false;

  int get count => _count;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await refresh();
    _subscribeRealtime();
  }

  void _subscribeRealtime() {
    try {
      final client = Supabase.instance.client;
      _channel = client
          .channel('admin_product_transfers_in_transit_badge')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'product_transfers',
            callback: (_) {
              unawaited(refresh());
            },
          )
          .subscribe();
    } catch (error, stackTrace) {
      debugPrint('ProductTransfersInTransitCounter realtime: $error');
      debugPrint('$stackTrace');
    }
  }

  /// [storeFilter] = `to_store` (входящие); `null` — все в пути (как у админа на вкладке).
  Future<void> refresh({String? storeFilter}) async {
    try {
      final next = await _database.countProductTransfersInTransit(
        storeFilter: storeFilter,
      );
      if (next != _count) {
        _count = next;
        notifyListeners();
      }
    } catch (error, stackTrace) {
      debugPrint('ProductTransfersInTransitCounter.refresh: $error');
      debugPrint('$stackTrace');
    }
  }

  @override
  void dispose() {
    final ch = _channel;
    if (ch != null) {
      unawaited(ch.unsubscribe());
    }
    super.dispose();
  }
}