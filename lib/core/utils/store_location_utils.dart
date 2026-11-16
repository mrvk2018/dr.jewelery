import 'package:flutter/material.dart';

/// Коды точек (совпадают с `products.store_location` и POS-трансферами).
abstract final class StoreLocationCode {
  static const icn = 'ICN';
  static const ans = 'ANS';
  static const defaultCode = icn;
}

String? _readOriginalMart(Map<String, dynamic>? row) {
  if (row == null) return null;
  final raw = row['warehouse_attributes'];
  if (raw is Map) {
    final mart = raw['original_mart'];
    if (mart != null) {
      final text = mart.toString().trim();
      if (text.isNotEmpty) return text;
    }
  }
  return null;
}

/// Нормализация кода `ICN` | `ANS` (DrJaw Mart, store_location, original_mart).
String normalizeStoreLocationCode({
  String? storeLocation,
  String? originalMart,
  Map<String, dynamic>? productRow,
}) {
  final fromRow = storeLocation?.trim().toUpperCase();
  if (fromRow == StoreLocationCode.ans || fromRow == StoreLocationCode.icn) {
    return fromRow!;
  }

  final mart = (originalMart ?? _readOriginalMart(productRow))?.trim() ?? '';
  if (mart.isNotEmpty) {
    final lower = mart.toLowerCase();
    if (mart == 'D.Y №2' ||
        lower.contains('№2') ||
        lower.contains('d.y') ||
        lower == 'ans' ||
        lower.contains('ансан')) {
      return StoreLocationCode.ans;
    }
    if (mart == 'Основной магазин') {
      return StoreLocationCode.icn;
    }
  }

  return StoreLocationCode.defaultCode;
}

String storeLocationCodeFromProductRow(Map<String, dynamic> row) {
  return normalizeStoreLocationCode(
    storeLocation: row['store_location']?.toString(),
    productRow: row,
  );
}

/// Человекочитаемая подпись для админки.
String storeLocationDisplayLabel(
  String code, {
  String? originalMart,
}) {
  switch (code.toUpperCase()) {
    case StoreLocationCode.ans:
      return 'Ансан';
    case StoreLocationCode.icn:
      return 'Инчхон';
    default:
      final mart = originalMart?.trim() ?? '';
      if (mart == 'D.Y №2') return 'Ансан';
      if (mart == 'Основной магазин') return 'Инчхон';
      return 'Инчхон';
  }
}

String storeLocationDisplayLabelForRow(Map<String, dynamic> row) {
  final code = storeLocationCodeFromProductRow(row);
  return storeLocationDisplayLabel(
    code,
    originalMart: _readOriginalMart(row),
  );
}

/// Цвета бейджа «Магазин» в таблице админки.
({Color bg, Color fg}) storeLocationBadgeColors(String code) {
  switch (code.toUpperCase()) {
    case StoreLocationCode.ans:
      return (
        bg: const Color(0xFFE8F0FE),
        fg: const Color(0xFF1A4FB8),
      );
    case StoreLocationCode.icn:
    default:
      return (
        bg: const Color(0xFFFFF3E0),
        fg: const Color(0xFFB45309),
      );
  }
}

class ShowroomStoreSelectionStats {
  const ShowroomStoreSelectionStats({
    this.count = 0,
    this.weightGrams = 0,
    this.priceKrw = 0,
  });

  final int count;
  final double weightGrams;
  final int priceKrw;
}

Map<String, ShowroomStoreSelectionStats> computeShowroomStatsByStore({
  required Iterable<Map<String, dynamic>> products,
  required int Function(Map<String, dynamic> row) priceKrwForRow,
  required double Function(Map<String, dynamic> row) weightGramsForRow,
}) {
  final buckets = <String, ShowroomStoreSelectionStats>{
    StoreLocationCode.icn: const ShowroomStoreSelectionStats(),
    StoreLocationCode.ans: const ShowroomStoreSelectionStats(),
  };

  for (final row in products) {
    final code = storeLocationCodeFromProductRow(row);
    final prev = buckets[code] ?? const ShowroomStoreSelectionStats();
    buckets[code] = ShowroomStoreSelectionStats(
      count: prev.count + 1,
      weightGrams: prev.weightGrams + weightGramsForRow(row),
      priceKrw: prev.priceKrw + priceKrwForRow(row),
    );
  }
  return buckets;
}