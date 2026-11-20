import '../../../core/constants/jewelry_category_subtypes.dart';
import '../../../core/utils/product_size_utils.dart';
import '../../../core/utils/showroom_price_utils.dart';
import '../../../core/utils/won_format.dart';

/// DTO гантельки 12×60 mm: лицо / оборот / QR.
class JewelryLabelData {
  const JewelryLabelData({
    required this.category,
    this.subtype = '',
    required this.weightLine,
    this.sizeLine = '',
    required this.showroomPriceKrw,
    required this.insertsLine,
    required this.descriptionLine,
    required this.qrPayload,
    required this.sku,
    this.productName = '',
    this.probeSizeWeightLine = '',
  });

  final String category;
  final String subtype;
  final String weightLine;
  final String sizeLine;
  final int showroomPriceKrw;
  final String insertsLine;
  final String descriptionLine;
  final String qrPayload;
  final String sku;

  /// Legacy / TSPL fallback.
  final String productName;
  final String probeSizeWeightLine;

  String get showroomPriceLine =>
      formatShowroomWonForJewelryLabel(showroomPriceKrw);

  String get priceLine => 'Цена: ${formatWonForLabel(showroomPriceKrw)}';

  factory JewelryLabelData.fromProductMap(Map<String, dynamic> map) {
    final nameText = _resolveProductName(map);
    final parsed = parseJewelryProductCategoryFromRow(
      nameText: nameText,
      categoryColumn: map['category']?.toString(),
    );

    final category = parsed.isOther
        ? (map['category']?.toString().trim().isNotEmpty == true
            ? map['category'].toString().trim()
            : nameText)
        : parsed.mainCategory;

    final subtype = parsed.catalogSubtype ??
        parsed.customSubtype ??
        _subtypeFromName(nameText, category);

    final weightRaw = map['weight_grams'];
    final weightLine = _formatWeightLine(weightRaw);

    final sizeNum = productDisplaySizeFromRow(map);
    final sizeLine = sizeNum > 0 ? _formatNum(sizeNum) : '';

    final showroomPrice = productShowroomListPriceKrw(map);

    final inserts = _resolveInserts(map);
    final description = _resolveDescription(map);

    final sku = (map['sku'] ?? '').toString().trim();
    final productId = map['id']?.toString().trim() ?? '';
    final qr = productId.isNotEmpty
        ? productId
        : (map['qr_code_payload'] ?? sku).toString().trim();

    final probe = _probeFromMap(map);
    final legacyProbeLine = [
      probe,
      sizeLine,
      weightRaw != null ? _formatNum(weightRaw) : '',
    ].where((p) => p.isNotEmpty).join(' / ');

    return JewelryLabelData(
      category: category.isEmpty ? '—' : category,
      subtype: subtype,
      weightLine: weightLine.isEmpty ? '—' : weightLine,
      sizeLine: sizeLine,
      showroomPriceKrw: showroomPrice.clamp(0, 999999999),
      insertsLine: inserts,
      descriptionLine: description,
      qrPayload: qr,
      sku: sku.isEmpty ? '—' : sku,
      productName: nameText,
      probeSizeWeightLine:
          legacyProbeLine.isEmpty ? '—' : legacyProbeLine,
    );
  }

  static String _subtypeFromName(String name, String category) {
    if (!name.contains(kJewelryCategorySubtypeSeparator)) return '';
    final parts = name.split(kJewelryCategorySubtypeSeparator);
    if (parts.length < 2) return '';
    if (parts.first.trim().toLowerCase() != category.toLowerCase()) {
      return '';
    }
    return parts.sublist(1).join(kJewelryCategorySubtypeSeparator).trim();
  }

  static String _formatWeightLine(Object? value) {
    if (value == null) return '';
    final text = _formatNum(value);
    if (text.isEmpty) return '';
    return '$text г';
  }

  static String _probeFromMap(Map<String, dynamic> map) {
    final metal = map['metal_type']?.toString().trim() ?? '';
    if (metal.isNotEmpty) return metal;
    return map['metal']?.toString().trim() ?? '';
  }

  static String _resolveInserts(Map<String, dynamic> map) {
    final gems = map['gem_inserts']?.toString().trim() ?? '';
    if (gems.isNotEmpty && gems != '—' && gems != '-') return gems;
    final insert = map['insert']?.toString().trim() ?? '';
    if (insert.isNotEmpty && insert != '—' && insert != '-') {
      return insert;
    }
    return 'Без камней';
  }

  static String _resolveDescription(Map<String, dynamic> map) {
    final raw = map['description'];
    if (raw is Map) {
      for (final key in ['ru', 'ko', 'en']) {
        final t = raw[key]?.toString().trim();
        if (t != null && t.isNotEmpty) return t;
      }
    }
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    final notes = map['notes']?.toString().trim() ?? '';
    if (notes.isNotEmpty) return notes;
    return '';
  }

  static String _formatNum(Object? value) {
    if (value == null) return '';
    if (value is num) {
      final d = value.toDouble();
      if (d == d.roundToDouble()) return '${d.toInt()}';
      return d.toStringAsFixed(2);
    }
    return value.toString().trim();
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