import '../../../core/utils/won_format.dart';

/// DTO данных для печати бирки и превью.
class JewelryLabelData {
  const JewelryLabelData({
    required this.productName,
    required this.sku,
    required this.probeSizeWeightLine,
    required this.priceKrw,
    this.qrPayload = '',
  });

  final String productName;
  final String sku;
  final String probeSizeWeightLine;
  final int priceKrw;
  final String qrPayload;

  String get priceLine => 'Цена: ${formatWonForLabel(priceKrw)}';

  /// Маппинг строки `products` (Supabase Pro SSOT).
  factory JewelryLabelData.fromProductMap(Map<String, dynamic> map) {
    final name = _resolveProductName(map);

    final sku = (map['sku'] ?? map['id'] ?? '').toString().trim();

    final probe = _probeFromMap(map);
    final size = _formatNum(map['size_value']);
    final weight = _formatNum(map['weight_grams']);
    final probeLine = [probe, size, weight]
        .where((part) => part.isNotEmpty)
        .join(' / ');

    final price = (map['sale_price'] as num?)?.toInt() ??
        (map['base_price'] as num?)?.toInt() ??
        (map['price_krw'] as num?)?.toInt() ??
        0;

    final qr = (map['qr_code_payload'] ?? sku).toString().trim();

    return JewelryLabelData(
      productName: name,
      sku: sku.isEmpty ? '—' : sku,
      probeSizeWeightLine: probeLine.isEmpty ? '—' : probeLine,
      priceKrw: price.clamp(0, 999999999),
      qrPayload: qr,
    );
  }

  static String _probeFromMap(Map<String, dynamic> map) {
    final metal = map['metal_type']?.toString().trim() ?? '';
    if (metal.isNotEmpty) return metal;
    return map['metal']?.toString().trim() ?? '';
  }

  static String _formatNum(Object? value) {
    if (value == null) return '';
    if (value is num) {
      final d = value.toDouble();
      if (d == d.roundToDouble()) return '${d.toInt()}';
      return d.toStringAsFixed(2);
    }
    final text = value.toString().trim();
    return text;
  }

  static String _resolveProductName(Map<String, dynamic> map) {
    final rawName = map['name'];
    if (rawName is Map) {
      for (final key in ['ru', 'ko', 'en', 'kk', 'uz']) {
        final localized = rawName[key]?.toString().trim();
        if (localized != null && localized.isNotEmpty) return localized;
      }
    }
    return _firstNonEmpty([
      map['product_name']?.toString(),
      rawName?.toString(),
      map['notes']?.toString(),
      map['sku']?.toString(),
    ]);
  }

  static String _firstNonEmpty(List<String?> candidates) {
    for (final c in candidates) {
      final t = c?.trim();
      if (t != null && t.isNotEmpty) return t;
    }
    return 'Изделие';
  }
}
