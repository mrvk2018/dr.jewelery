import 'dart:convert';

/// Разбор QR с бирки TSC / дубликата: в первую очередь `products.id`, иначе payload / SKU.
abstract final class JewelryQrParser {
  static final _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static final _urlProductIdPattern = RegExp(
    r'(?:/products?/|product_id=|id=)([A-Za-z0-9_-]+)',
  );

  /// Результат парсинга одной строки (сканер / USB HID).
  static JewelryQrParseResult parse(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const JewelryQrParseResult.empty();
    }

    if (_uuidPattern.hasMatch(trimmed)) {
      return JewelryQrParseResult(productId: trimmed, sku: null, raw: trimmed);
    }

  if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      try {
        final map = jsonDecode(trimmed);
        if (map is Map) {
          final id = _firstNonEmpty([
            map['product_id']?.toString(),
            map['productId']?.toString(),
            map['id']?.toString(),
          ]);
          final sku = _firstNonEmpty([
            map['sku']?.toString(),
            map['articul']?.toString(),
          ]);
          if (id != null) {
            return JewelryQrParseResult(productId: id, sku: sku, raw: trimmed);
          }
          if (sku != null) {
            return JewelryQrParseResult(productId: null, sku: sku, raw: trimmed);
          }
        }
      } catch (_) {
        // not JSON — fall through
      }
    }

    if (trimmed.contains('://')) {
      final match = _urlProductIdPattern.firstMatch(trimmed);
      if (match != null) {
        final id = match.group(1)?.trim();
        if (id != null && id.isNotEmpty) {
          return JewelryQrParseResult(productId: id, sku: null, raw: trimmed);
        }
      }
    }

    if (_looksLikeProductId(trimmed)) {
      return JewelryQrParseResult(productId: trimmed, sku: null, raw: trimmed);
    }

    return JewelryQrParseResult(productId: null, sku: trimmed, raw: trimmed);
  }

  static bool _looksLikeProductId(String value) {
    if (value.length < 4 || value.length > 64) return false;
    if (value.contains(' ')) return false;
    return RegExp(r'^[A-Za-z0-9._-]+$').hasMatch(value);
  }

  static String? _firstNonEmpty(List<String?> values) {
    for (final v in values) {
      final t = v?.trim();
      if (t != null && t.isNotEmpty) return t;
    }
    return null;
  }
}

class JewelryQrParseResult {
  const JewelryQrParseResult({
    required this.productId,
    required this.sku,
    required this.raw,
  });

  const JewelryQrParseResult.empty()
      : productId = null,
        sku = null,
        raw = '';

  final String? productId;
  final String? sku;
  final String raw;

  String get lookupKey => productId ?? sku ?? raw;
}