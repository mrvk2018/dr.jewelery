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
      'image_url, photo_status, raw_legacy_payload, migration_meta';

  static const defaultPageSize = 50;

  Future<List<SalesHistoryRow>> fetchPage({
    required int pageIndex,
    int pageSize = defaultPageSize,
    String? soldDateKst,
  }) async {
    final from = pageIndex * pageSize;
    final to = from + pageSize - 1;

    try {
      var query = _client.from(_table).select(_listColumns);

      if (soldDateKst != null && soldDateKst.isNotEmpty) {
        query = query.eq('sold_date_kst', soldDateKst);
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

  /// SUM(price_krw) за календарный день KST (пагинация только price_krw).
  Future<int> sumPriceKrwForSoldDateKst(String soldDateKst) async {
    if (soldDateKst.trim().isEmpty) return 0;

    var total = 0;
    var from = 0;
    const chunk = 1000;

    try {
      for (;;) {
        final rows = await _client
            .from(_table)
            .select('price_krw')
            .eq('sold_date_kst', soldDateKst)
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
      debugPrint('SalesHistoryRepository.sumPriceKrwForSoldDateKst failed: $error');
      debugPrint('$stackTrace');
      rethrow;
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
