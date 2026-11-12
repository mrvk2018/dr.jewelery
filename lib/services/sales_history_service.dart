import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/services/database_service.dart';
import '../models/sales_history_row.dart';

class SalesHistoryRepository {
  SalesHistoryRepository({
    SupabaseClient? client,
    DatabaseService? database,
  })  : _client = client ?? Supabase.instance.client,
        _database = database ?? DatabaseService.create();

  final SupabaseClient _client;
  final DatabaseService _database;

  static const _table = 'sales_history';
  static const _listColumns =
      'id, legacy_id, sku, price_krw, sold_at_utc, sold_date_kst, '
      'image_url, photo_status, source_system, raw_legacy_payload, migration_meta';

  static const rpcProcessPosProductReturn = 'process_pos_product_return';
  static const posReturnProductIdParam = 'p_product_id';
  static const posReturnReasonParam = 'p_reason';
  static const posReturnAdminNameParam = 'p_admin_name';

  static const defaultPageSize = 50;

  /// `products.id` → `status` (лёгкий батч для кнопки возврата).
  Future<Map<String, String>> fetchProductStatusesByIds(Set<String> productIds) async {
    if (productIds.isEmpty) return const {};
    final ids = productIds.where((id) => id.trim().isNotEmpty).toList();
    if (ids.isEmpty) return const {};

    final statuses = <String, String>{};
    const chunkSize = 80;

    try {
      for (var offset = 0; offset < ids.length; offset += chunkSize) {
        final end = (offset + chunkSize > ids.length) ? ids.length : offset + chunkSize;
        final chunk = ids.sublist(offset, end);
        final rows = await _client
            .from('products')
            .select('id, status')
            .inFilter('id', chunk);
        for (final row in rows) {
          final map = Map<String, dynamic>.from(row);
          final id = map['id']?.toString();
          final status = map['status']?.toString().trim();
          if (id != null && id.isNotEmpty && status != null && status.isNotEmpty) {
            statuses[id] = status;
          }
        }
      }
      return statuses;
    } catch (error, stackTrace) {
      debugPrint('SalesHistoryRepository.fetchProductStatusesByIds failed: $error');
      debugPrint('$stackTrace');
      rethrow;
    }
  }

  Future<List<SalesHistoryRow>> fetchPage({
    required int pageIndex,
    int pageSize = defaultPageSize,
    required String soldDateKstStart,
    required String soldDateKstEnd,
  }) async {
    final from = pageIndex * pageSize;
    final to = from + pageSize - 1;

    try {
      var query = _client.from(_table).select(_listColumns);

      final start = soldDateKstStart.trim();
      final end = soldDateKstEnd.trim();
      if (start.isNotEmpty) {
        query = query.gte('sold_date_kst', start);
      }
      if (end.isNotEmpty) {
        query = query.lte('sold_date_kst', end);
      }

      final rows = await query
          .order('sold_date_kst', ascending: false)
          .order('legacy_id', ascending: false)
          .range(from, to);
      return rows
          .map((row) => SalesHistoryRow.fromMap(Map<String, dynamic>.from(row)))
          .toList();
    } catch (error, stackTrace) {
      debugPrint('SalesHistoryRepository.fetchPage failed: $error');
      debugPrint('$stackTrace');
      rethrow;
    }
  }

  /// SUM(price_krw) за диапазон sold_date_kst (включительно, KST).
  Future<int> sumPriceKrwForSoldDateRangeKst(
    String soldDateKstStart,
    String soldDateKstEnd,
  ) async {
    final start = soldDateKstStart.trim();
    final end = soldDateKstEnd.trim();
    if (start.isEmpty || end.isEmpty) return 0;

    var total = 0;
    var from = 0;
    const chunk = 1000;

    try {
      for (;;) {
        final rows = await _client
            .from(_table)
            .select('price_krw')
            .gte('sold_date_kst', start)
            .lte('sold_date_kst', end)
            .order('legacy_id')
            .range(from, from + chunk - 1);

        if (rows.isEmpty) break;

        for (final row in rows) {
          final map = Map<String, dynamic>.from(row);
          final raw = map['price_krw'];
          if (raw is num) {
            total += raw.toInt();
          } else {
            total += int.tryParse(raw?.toString() ?? '') ?? 0;
          }
        }

        if (rows.length < chunk) break;
        from += chunk;
      }
      return total;
    } catch (error, stackTrace) {
      debugPrint('SalesHistoryRepository.sumPriceKrwForSoldDateRangeKst failed: $error');
      debugPrint('$stackTrace');
      rethrow;
    }
  }

  /// POS-возврат по `products.id` (`process_pos_product_return`).
  Future<void> processPosProductReturn({
    required String productId,
    required String reason,
    required String adminName,
  }) async {
    final id = productId.trim();
    final r = reason.trim();
    final admin = adminName.trim();
    if (id.isEmpty || r.isEmpty || admin.isEmpty) {
      throw StateError('Укажите product_id, причину и имя администратора');
    }
    try {
      final result = await _client.rpc(
        rpcProcessPosProductReturn,
        params: {
          posReturnProductIdParam: id,
          posReturnReasonParam: r,
          posReturnAdminNameParam: admin,
        },
      );
      if (result is Map) {
        final map = Map<String, dynamic>.from(result);
        final ok = map['ok'] == true || map['success'] == true;
        if (!ok) {
          final err = map['error']?.toString() ?? map['message']?.toString();
          throw StateError(err ?? 'Возврат не выполнен');
        }
      }
    } on PostgrestException catch (error, stackTrace) {
      debugPrint('SalesHistoryRepository.processPosProductReturn: $error');
      debugPrint('$stackTrace');
      throw StateError(error.message);
    }
  }

  /// Сторно продажи + возврат SKU на витрину (`process_product_return_manual`).
  Future<SalesHistoryRow> processProductReturn(String sku) async {
    final result = await _database.processProductReturn(sku);
    final reversalId = result['reversal_id']?.toString() ?? '';
    if (reversalId.isNotEmpty) {
      try {
        final row = await _client
            .from(_table)
            .select(_listColumns)
            .eq('id', reversalId)
            .maybeSingle();
        if (row != null) {
          return SalesHistoryRow.fromMap(Map<String, dynamic>.from(row));
        }
      } catch (error, stackTrace) {
        debugPrint('SalesHistoryRepository processProductReturn fetch: $error');
        debugPrint('$stackTrace');
      }
    }

    final priceRaw = result['price_krw'];
    final priceKrw = priceRaw is num ? priceRaw.toInt() : 0;
    return SalesHistoryRow(
      id: reversalId,
      legacyId: result['reversal_legacy_id']?.toString() ?? '',
      sku: result['sku']?.toString() ?? sku.trim(),
      priceKrw: priceKrw,
      soldDateKst: result['sold_date_kst']?.toString(),
      migrationMeta: const {'type': 'return'},
    );
  }
}
