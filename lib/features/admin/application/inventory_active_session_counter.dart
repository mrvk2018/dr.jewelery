import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/database_service.dart';

/// Бейдж «Идёт ревизия» (inventory_sessions.status = active).
class InventoryActiveSessionCounter extends ChangeNotifier {
  InventoryActiveSessionCounter(this._database);

  final DatabaseService _database;
  bool _active = false;
  RealtimeChannel? _channel;
  bool _started = false;

  bool get hasActiveSession => _active;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await refresh();
    _channel = Supabase.instance.client
        .channel('inventory_sessions_active_badge')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'inventory_sessions',
          callback: (_) {
            unawaited(refresh());
          },
        )
        .subscribe();
  }

  Future<void> refresh() async {
    try {
      final session = await _database.fetchActiveInventorySession();
      final next = session != null;
      if (next != _active) {
        _active = next;
        notifyListeners();
      }
    } catch (error, stackTrace) {
      debugPrint('InventoryActiveSessionCounter.refresh: $error');
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