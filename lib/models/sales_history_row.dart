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
  });

  final int totalSumKrw;
  final int totalCount;
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
    return SalesHistorySummary(
      totalSumKrw: _numToInt(map['total_sum_krw']),
      totalCount: _numToInt(map['total_count']),
      goldWeightGrams: _numToDouble(map['gold_weight_grams']),
      goldSumKrw: _numToInt(map['gold_sum_krw']),
      goldCount: _numToInt(map['gold_count']),
      silverWeightGrams: _numToDouble(map['silver_weight_grams']),
      silverSumKrw: _numToInt(map['silver_sum_krw']),
      silverCount: _numToInt(map['silver_count']),
      otherCount: _numToInt(map['other_count']),
    );
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