class SalesHistoryRow {
  const SalesHistoryRow({
    required this.id,
    required this.legacyId,
    required this.sku,
    required this.priceKrw,
    this.soldAtUtc,
    this.soldDateKst,
    this.imageUrl,
    this.photoStatus,
    this.sourceSystem,
    this.rawLegacyPayload,
    this.migrationMeta,
  });

  final String id;
  final String legacyId;
  final String sku;
  final int priceKrw;
  final DateTime? soldAtUtc;
  final String? soldDateKst;
  final String? imageUrl;
  final String? photoStatus;
  final String? sourceSystem;
  final Map<String, dynamic>? rawLegacyPayload;
  final Map<String, dynamic>? migrationMeta;

  bool get isReturnLine =>
      priceKrw < 0 ||
      migrationMeta?['type']?.toString() == 'return' ||
      legacyId.startsWith('return_');

  /// `products.id` для POS/PWA-возврата (`process_pos_product_return`).
  String? get resolvedProductId {
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

  /// Базовая PWA-строка, которую теоретически можно вернуть через POS (без учёта сторно / products).
  bool get canProcessPosReturn {
    if (isReturnLine || sku.isEmpty) return false;
    if (resolvedSourceSystem == 'DrJaw') return false;
    if (!isPwaSale) return false;
    final productId = resolvedProductId;
    return productId != null && productId.isNotEmpty;
  }

  /// Собирает `legacy_id` продаж, уже покрытых сторно на загруженных строках.
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

  /// Последняя (самая свежая) PWA-продажа на `products.id` среди загруженных строк.
  static Map<String, String> latestPwaSaleLegacyByProductId(
    Iterable<SalesHistoryRow> rows,
  ) {
    final latestRowByProduct = <String, SalesHistoryRow>{};
    for (final row in rows) {
      if (row.isReturnLine || !row.isPwaSale || row.priceKrw <= 0) continue;
      final productId = row.resolvedProductId;
      if (productId == null || productId.isEmpty) continue;
      final existing = latestRowByProduct[productId];
      if (existing == null || _compareSaleRecency(row, existing) > 0) {
        latestRowByProduct[productId] = row;
      }
    }
    return {
      for (final e in latestRowByProduct.entries) e.key: e.value.legacyId,
    };
  }

  static Set<String> pwaProductIdsFromRows(Iterable<SalesHistoryRow> rows) {
    return rows
        .where((row) => row.isPwaSale && !row.isReturnLine)
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

  SalesHistoryRow copyWith({
    String? id,
    String? legacyId,
    String? sku,
    int? priceKrw,
    DateTime? soldAtUtc,
    String? soldDateKst,
    String? imageUrl,
    String? photoStatus,
    String? sourceSystem,
    Map<String, dynamic>? rawLegacyPayload,
    Map<String, dynamic>? migrationMeta,
  }) {
    return SalesHistoryRow(
      id: id ?? this.id,
      legacyId: legacyId ?? this.legacyId,
      sku: sku ?? this.sku,
      priceKrw: priceKrw ?? this.priceKrw,
      soldAtUtc: soldAtUtc ?? this.soldAtUtc,
      soldDateKst: soldDateKst ?? this.soldDateKst,
      imageUrl: imageUrl ?? this.imageUrl,
      photoStatus: photoStatus ?? this.photoStatus,
      sourceSystem: sourceSystem ?? this.sourceSystem,
      rawLegacyPayload: rawLegacyPayload ?? this.rawLegacyPayload,
      migrationMeta: migrationMeta ?? this.migrationMeta,
    );
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
