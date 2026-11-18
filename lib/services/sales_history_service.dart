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

  static const rpcListReport = 'list_sales_history_report';
  static const rpcSummary = 'get_sales_history_summary';
  static const rpcProcessPosProductReturn = 'process_pos_product_return';
  static const posReturnProductIdParam = 'p_product_id';
  static const posReturnReasonParam = 'p_reason';
  static const posReturnAdminNameParam = 'p_admin_name';

  static const pDateFrom = 'p_date_from';
  static const pDateTo = 'p_date_to';
  static const pStore = 'p_store';
  static const pLimit = 'p_limit';
  static const pOffset = 'p_offset';

  static const defaultPageSize = 50;

  Future<List<SalesHistoryRow>> fetchPage({
    required int pageIndex,
    int pageSize = defaultPageSize,
    required String soldDateKstStart,
    required String soldDateKstEnd,
    String store = 'ALL',
  }) async {
    final start = soldDateKstStart.trim();
    final end = soldDateKstEnd.trim();
    if (start.isEmpty || end.isEmpty) return const [];

    try {
      final response = await _client.rpc(
        rpcListReport,
        params: {
          pDateFrom: start,
          pDateTo: end,
          pStore: store.trim().isEmpty ? 'ALL' : store.trim().toUpperCase(),
          pLimit: pageSize,
          pOffset: pageIndex * pageSize,
        },
      );
      if (response is! List) return const [];
      return response
          .map((row) => SalesHistoryRow.fromReportRpc(
                Map<String, dynamic>.from(row as Map),
              ))
          .toList();
    } catch (error, stackTrace) {
      debugPrint('SalesHistoryRepository.fetchPage failed: $error');
      debugPrint('$stackTrace');
      rethrow;
    }
  }

  Future<SalesHistorySummary> fetchSummary({
    required String soldDateKstStart,
    required String soldDateKstEnd,
    String store = 'ALL',
  }) async {
    final start = soldDateKstStart.trim();
    final end = soldDateKstEnd.trim();
    if (start.isEmpty || end.isEmpty) {
      return SalesHistorySummary.fromRpc(null);
    }

    try {
      final response = await _client.rpc(
        rpcSummary,
        params: {
          pDateFrom: start,
          pDateTo: end,
          pStore: store.trim().isEmpty ? 'ALL' : store.trim().toUpperCase(),
        },
      );
      return SalesHistorySummary.fromRpc(response);
    } catch (error, stackTrace) {
      debugPrint('SalesHistoryRepository.fetchSummary failed: $error');
      debugPrint('$stackTrace');
      rethrow;
    }
  }

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

  Future<SalesHistoryRow> processProductReturn(String sku) async {
    final result = await _database.processProductReturn(sku);
    final priceRaw = result['price_krw'];
    final priceKrw = priceRaw is num ? priceRaw.toInt() : 0;
    return SalesHistoryRow(
      id: result['reversal_id']?.toString() ?? '',
      legacyId: result['reversal_legacy_id']?.toString() ?? '',
      sku: result['sku']?.toString() ?? sku.trim(),
      priceKrw: priceKrw,
      soldDateKst: result['sold_date_kst']?.toString(),
      migrationMeta: const {'type': 'return'},
    );
  }
}