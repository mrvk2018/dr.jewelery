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
    this.rawLegacyPayload,
  });

  final String id;
  final String legacyId;
  final String sku;
  final int priceKrw;
  final DateTime? soldAtUtc;
  final String? soldDateKst;
  final String? imageUrl;
  final String? photoStatus;
  final Map<String, dynamic>? rawLegacyPayload;

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
      rawLegacyPayload: _parsePayload(map['raw_legacy_payload']),
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
