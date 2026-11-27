class SalesHistoryStoreFilter {
  const SalesHistoryStoreFilter(this.rpcValue, this.label);

  final String rpcValue;
  final String label;

  static const all = SalesHistoryStoreFilter('ALL', 'Все');
  static const icn = SalesHistoryStoreFilter('ICN', 'Инчхон');
  static const ans = SalesHistoryStoreFilter('ANS', 'Ансан');

  static const values = [all, icn, ans];
}

class SalesHistorySummary {
  const SalesHistorySummary({
    required this.totalSumKrw,
    required this.totalCount,
    required this.goldWeightGrams,
    required this.goldSumKrw,
    required this.goldCount,
    required this.silverWeightGrams,
    required this.silverSumKrw,
    required this.silverCount,
    required this.otherCount,
    this.grossSalesKrw = 0,
    this.tradeInScrapKrw = 0,
    this.tradeInBatchCount = 0,
    this.netCashKrw = 0,
    this.shiftCashKrw = 0,
    this.reservationCashKrw = 0,
    this.reservationsNetKrw = 0,
    this.returnsSumKrw = 0,
    this.returnsCount = 0,
    this.cashKrw = 0,
    this.cardKrw = 0,
    this.transferKrw = 0,
    this.hasShiftCash = false,
    this.byMethod = const {},
  });

  final int totalSumKrw;
  final int totalCount;
  final int grossSalesKrw;
  final int tradeInScrapKrw;
  final int tradeInBatchCount;
  final int netCashKrw;
  final int shiftCashKrw;
  final int reservationCashKrw;
  final int reservationsNetKrw;
  final int returnsSumKrw;
  final int returnsCount;
  final int cashKrw;
  final int cardKrw;
  final int transferKrw;
  final bool hasShiftCash;
  final Map<String, int> byMethod;
  final double goldWeightGrams;
  final int goldSumKrw;
  final int goldCount;
  final double silverWeightGrams;
  final int silverSumKrw;
  final int silverCount;
  final int otherCount;

  factory SalesHistorySummary.fromRpc(dynamic raw) {
    if (raw is! Map) {
      return const SalesHistorySummary(
        totalSumKrw: 0,
        totalCount: 0,
        grossSalesKrw: 0,
        tradeInScrapKrw: 0,
        tradeInBatchCount: 0,
        netCashKrw: 0,
        goldWeightGrams: 0,
        goldSumKrw: 0,
        goldCount: 0,
        silverWeightGrams: 0,
        silverSumKrw: 0,
        silverCount: 0,
        otherCount: 0,
      );
    }
    final map = Map<String, dynamic>.from(raw);
    final gross = _numToInt(map['gross_sales_krw']);
    final total = _numToInt(map['total_sum_krw']);
    final tradeIn = _numToInt(map['trade_in_scrap_krw']);
    final hasNet = map.containsKey('net_cash_krw');
    final hasShift = map.containsKey('shift_cash_krw');
    final netCash = _numToInt(map['net_cash_krw']);
    final resolvedNet =
        hasNet ? netCash : (tradeIn > 0 ? netCash : total);
    final shift = hasShift ? _numToInt(map['shift_cash_krw']) : resolvedNet;
    return SalesHistorySummary(
      totalSumKrw: total,
      totalCount: _numToInt(map['total_count']),
      grossSalesKrw: gross > 0 ? gross : total,
      tradeInScrapKrw: tradeIn,
      tradeInBatchCount: _numToInt(map['trade_in_batch_count']),
      netCashKrw: hasShift ? shift : resolvedNet,
      shiftCashKrw: shift,
      reservationCashKrw: _numToInt(map['reservation_cash_krw']),
      reservationsNetKrw: _numToInt(
        map['reservations_net_krw'] ?? map['reservation_cash_krw'],
      ),
      returnsSumKrw: _numToInt(map['returns_sum_krw']),
      returnsCount: _numToInt(map['returns_count']),
      cashKrw: _numToInt(map['cash_krw']),
      cardKrw: _numToInt(map['card_krw']),
      transferKrw: _numToInt(map['transfer_krw']),
      hasShiftCash: hasShift,
      byMethod: _methodMap(map['by_method']),
      goldWeightGrams: _numToDouble(map['gold_weight_grams']),
      goldSumKrw: _numToInt(map['gold_sum_krw']),
      goldCount: _numToInt(map['gold_count']),
      silverWeightGrams: _numToDouble(map['silver_weight_grams']),
      silverSumKrw: _numToInt(map['silver_sum_krw']),
      silverCount: _numToInt(map['silver_count']),
      otherCount: _numToInt(map['other_count']),
    );
  }

  SalesHistorySummary withShiftDrawer(Map<String, dynamic> shift) {
    final grossShift = _numToInt(shift['gross_sales_krw']);
    final methods = _methodMap(shift['by_method']);
    return SalesHistorySummary(
      totalSumKrw: totalSumKrw,
      totalCount: totalCount,
      grossSalesKrw: grossShift > 0 ? grossShift : grossSalesKrw,
      tradeInScrapKrw: _numToInt(shift['trade_in_scrap_krw']),
      tradeInBatchCount: tradeInBatchCount,
      netCashKrw: _numToInt(shift['shift_cash_krw']),
      shiftCashKrw: _numToInt(shift['shift_cash_krw']),
      reservationCashKrw: _numToInt(shift['reservation_cash_krw']),
      reservationsNetKrw: _numToInt(
        shift['reservations_net_krw'] ?? shift['reservation_cash_krw'],
      ),
      returnsSumKrw: _numToInt(shift['returns_sum_krw']),
      returnsCount: _numToInt(shift['returns_count']),
      cashKrw: _numToInt(shift['cash_krw'] ?? methods['cash']),
      cardKrw: _numToInt(shift['card_krw'] ?? methods['card']),
      transferKrw: _numToInt(shift['transfer_krw'] ?? methods['transfer']),
      hasShiftCash: true,
      byMethod: methods,
      goldWeightGrams: goldWeightGrams,
      goldSumKrw: goldSumKrw,
      goldCount: goldCount,
      silverWeightGrams: silverWeightGrams,
      silverSumKrw: silverSumKrw,
      silverCount: silverCount,
      otherCount: otherCount,
    );
  }

  static Map<String, int> _methodMap(Object? raw) {
    if (raw is! Map) return const {};
    return {
      for (final entry in raw.entries)
        entry.key.toString(): _numToInt(entry.value),
    };
  }

  static int _numToInt(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double _numToDouble(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class SalesHistoryRow {
  const SalesHistoryRow({
    required this.id,
    required this.legacyId,
    required this.sku,
    required this.priceKrw,
    this.productId,
    this.productName,
    this.weightGrams,
    this.listPriceKrw,
    this.discountPercent = 0,
    this.storeLocation,
    this.sellerName,
    this.sellerCode,
    this.manufacturer,
    this.paymentMethod,
    this.soldAtUtc,
    this.soldDateKst,
    this.imageUrl,
    this.photoStatus,
    this.sourceSystem,
    this.metalCategory,
    this.canReturn = false,
    this.rawLegacyPayload,
    this.migrationMeta,
    this.saleBatchId,
    this.scrapTradeInKrw = 0,
    this.netCashDeltaKrw,
    this.isTradeIn = false,
  });

  final String id;
  final String legacyId;
  final String sku;
  final int priceKrw;
  final String? productId;
  final String? productName;
  final double? weightGrams;
  final int? listPriceKrw;
  final int discountPercent;
  final String? storeLocation;
  final String? sellerName;
  final String? sellerCode;
  final String? manufacturer;
  final String? paymentMethod;
  final DateTime? soldAtUtc;
  final String? soldDateKst;
  final String? imageUrl;
  final String? photoStatus;
  final String? sourceSystem;
  final String? metalCategory;
  final bool canReturn;
  final Map<String, dynamic>? rawLegacyPayload;
  final Map<String, dynamic>? migrationMeta;
  final String? saleBatchId;
  final int scrapTradeInKrw;
  final int? netCashDeltaKrw;
  final bool isTradeIn;

  bool get isReturnLine =>
      priceKrw < 0 ||
      migrationMeta?['type']?.toString() == 'return' ||
      legacyId.startsWith('return_');

  bool get showsDiscount {
    if (discountPercent > 0) return true;
    final list = listPriceKrw;
    return list != null && list > priceKrw && priceKrw > 0;
  }

  int get displayListPriceKrw => listPriceKrw ?? priceKrw;

  String? get resolvedProductId {
    final direct = productId?.trim();
    if (direct != null && direct.isNotEmpty) return direct;

    final fromMeta = migrationMeta?['product_id']?.toString().trim();
    if (fromMeta != null && fromMeta.isNotEmpty) return fromMeta;

    final payload = rawLegacyPayload;
    if (payload != null) {
      for (final key in const ['id', 'product_id']) {
        final raw = payload[key]?.toString().trim();
        if (raw != null && raw.isNotEmpty) return raw;
      }
    }

    const prefix = 'pwa_id_';
    if (legacyId.startsWith(prefix)) {
      final id = legacyId.substring(prefix.length).trim();
      if (id.isNotEmpty) return id;
    }
    return null;
  }

  bool get isPwaSale => legacyId.startsWith('pwa_id_');

  String? get resolvedSourceSystem {
    final top = sourceSystem?.trim();
    if (top != null && top.isNotEmpty) return top;
    final meta = migrationMeta?['source_system']?.toString().trim();
    if (meta != null && meta.isNotEmpty) return meta;
    return null;
  }

  bool get canProcessPosReturn => canReturn;

  static Set<String> collectReversedLegacyIds(Iterable<SalesHistoryRow> rows) {
    final reversed = <String>{};
    for (final row in rows) {
      if (!row.isReturnLine) continue;
      final fromMeta = row.migrationMeta?['reverses_legacy_id']?.toString().trim();
      if (fromMeta != null && fromMeta.isNotEmpty) {
        reversed.add(fromMeta);
      }
      const prefix = 'return_';
      if (row.legacyId.startsWith(prefix)) {
        final original = row.legacyId.substring(prefix.length).trim();
        if (original.isNotEmpty) reversed.add(original);
      }
    }
    return reversed;
  }

  static Map<String, String> latestPwaSaleLegacyByProductId(
    Iterable<SalesHistoryRow> rows,
  ) {
    final latestRowByProduct = <String, SalesHistoryRow>{};
    for (final row in rows) {
      if (row.isReturnLine || !row.isPwaSale || row.priceKrw <= 0) continue;
      final pid = row.resolvedProductId;
      if (pid == null || pid.isEmpty) continue;
      final existing = latestRowByProduct[pid];
      if (existing == null || _compareSaleRecency(row, existing) > 0) {
        latestRowByProduct[pid] = row;
      }
    }
    return {
      for (final e in latestRowByProduct.entries) e.key: e.value.legacyId,
    };
  }

  static Set<String> pwaProductIdsFromRows(Iterable<SalesHistoryRow> rows) {
    return rows
        .map((row) => row.resolvedProductId)
        .whereType<String>()
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  static int _compareSaleRecency(SalesHistoryRow a, SalesHistoryRow b) {
    final aUtc = a.soldAtUtc?.millisecondsSinceEpoch;
    final bUtc = b.soldAtUtc?.millisecondsSinceEpoch;
    if (aUtc != null && bUtc != null) {
      if (aUtc != bUtc) return aUtc.compareTo(bUtc);
    } else if (aUtc != null) {
      return 1;
    } else if (bUtc != null) {
      return -1;
    }
    final aKst = a.soldDateKst ?? '';
    final bKst = b.soldDateKst ?? '';
    if (aKst != bKst) return aKst.compareTo(bKst);
    return a.legacyId.compareTo(b.legacyId);
  }

  factory SalesHistoryRow.fromReportRpc(Map<String, dynamic> map) {
    return SalesHistoryRow(
      id: map['id']?.toString() ?? '',
      legacyId: map['legacy_id']?.toString() ?? '',
      sku: map['sku']?.toString().trim() ?? '',
      priceKrw: _parseKrw(map['price_krw']),
      productId: map['product_id']?.toString().trim(),
      productName: map['product_name']?.toString().trim(),
      weightGrams: _parseDouble(map['weight_grams']),
      listPriceKrw: _parseKrwOpt(map['list_price_krw']),
      discountPercent: _parseKrw(map['discount_percent']),
      storeLocation: map['store_location']?.toString().trim(),
      sellerName: map['seller_name']?.toString().trim(),
      sellerCode: map['seller_code']?.toString().trim(),
      manufacturer: map['manufacturer']?.toString().trim(),
      paymentMethod: map['payment_method']?.toString().trim(),
      soldAtUtc: _parseDateTime(map['sold_at_utc']),
      soldDateKst: map['sold_date_kst']?.toString().trim(),
      imageUrl: map['image_url']?.toString().trim(),
      metalCategory: map['metal_category']?.toString().trim(),
      sourceSystem: map['source_system']?.toString().trim(),
      canReturn: map['can_return'] == true,
      saleBatchId: map['sale_batch_id']?.toString().trim(),
      scrapTradeInKrw: _parseKrw(map['scrap_trade_in_krw']),
      netCashDeltaKrw: _parseKrwOpt(map['net_cash_delta_krw']),
      isTradeIn: map['is_trade_in'] == true,
    );
  }

  factory SalesHistoryRow.fromMap(Map<String, dynamic> map) {
    return SalesHistoryRow(
      id: map['id']?.toString() ?? '',
      legacyId: map['legacy_id']?.toString() ?? '',
      sku: map['sku']?.toString().trim() ?? '',
      priceKrw: _parseKrw(map['price_krw']),
      soldAtUtc: _parseDateTime(map['sold_at_utc']),
      soldDateKst: map['sold_date_kst']?.toString().trim(),
      imageUrl: map['image_url']?.toString().trim(),
      photoStatus: map['photo_status']?.toString().trim(),
      sourceSystem: map['source_system']?.toString().trim(),
      rawLegacyPayload: _parsePayload(map['raw_legacy_payload']),
      migrationMeta: _parsePayload(map['migration_meta']),
    );
  }

  static int? _parseKrwOpt(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static double? _parseDouble(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static int _parseKrw(Object? value) {
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static DateTime? _parseDateTime(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toUtc();
    return DateTime.tryParse(value.toString())?.toUtc();
  }

  static Map<String, dynamic>? _parsePayload(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return null;
  }
}

/// Метаданные визуальной группы в «Истории продаж» (только Trade-In с приёмом лома).
class SalesRowGroupMeta {
  const SalesRowGroupMeta({
    required this.groupKey,
    required this.groupSize,
    required this.isFirstInGroup,
    this.groupColorIndex,
  });

  final String groupKey;
  final int groupSize;
  final bool isFirstInGroup;
  final int? groupColorIndex;

  bool get isMultiItemGroup => groupSize > 1;

  bool get showBatchCashSummary => groupSize <= 1 || isFirstInGroup;

  static const SalesRowGroupMeta solo = SalesRowGroupMeta(
    groupKey: '',
    groupSize: 1,
    isFirstInGroup: true,
    groupColorIndex: null,
  );
}

/// Ключ одного Trade-In чека с приёмом лома; `null` — обычная продажа (без группировки).
String? salesHistoryTradeInGroupKey(SalesHistoryRow row) {
  if (!row.isTradeIn || row.scrapTradeInKrw <= 0) return null;
  final batch = row.saleBatchId?.trim();
  if (batch != null && batch.isNotEmpty) return 'batch:$batch';
  final sold = row.soldAtUtc?.toIso8601String() ??
      row.soldDateKst?.trim() ??
      '';
  final sellerCode = row.sellerCode?.trim();
  final seller = (sellerCode != null && sellerCode.isNotEmpty)
      ? sellerCode
      : (row.sellerName?.trim() ?? '');
  return 'ti:$sold|$seller|${row.scrapTradeInKrw}';
}

List<SalesRowGroupMeta> computeSalesHistoryGroupMeta(
  Iterable<SalesHistoryRow> rows,
) {
  final list = rows.toList();
  if (list.isEmpty) return const [];

  final counts = <String, int>{};
  for (final row in list) {
    final key = salesHistoryTradeInGroupKey(row);
    if (key != null) {
      counts[key] = (counts[key] ?? 0) + 1;
    }
  }

  final seenFirst = <String>{};
  final colorByKey = <String, int>{};
  var multiGroupCounter = 0;
  final metas = <SalesRowGroupMeta>[];

  for (final row in list) {
    final key = salesHistoryTradeInGroupKey(row);
    if (key == null) {
      metas.add(
        SalesRowGroupMeta(
          groupKey: 'solo:${row.legacyId}',
          groupSize: 1,
          isFirstInGroup: true,
          groupColorIndex: null,
        ),
      );
      continue;
    }

    final size = counts[key] ?? 1;
    final isFirst = !seenFirst.contains(key);
    if (isFirst) seenFirst.add(key);

    int? colorIndex;
    if (size > 1) {
      if (!colorByKey.containsKey(key)) {
        colorByKey[key] = multiGroupCounter % 3;
        multiGroupCounter++;
      }
      colorIndex = colorByKey[key];
    }

    metas.add(
      SalesRowGroupMeta(
        groupKey: key,
        groupSize: size,
        isFirstInGroup: isFirst,
        groupColorIndex: colorIndex,
      ),
    );
  }
  return metas;
}