import 'package:flutter/material.dart';

/// Коды точек (совпадают с `products.store_location` и POS-трансферами).
abstract final class StoreLocationCode {
  static const icn = 'ICN';
  static const ans = 'ANS';
  static const defaultCode = icn;

  /// Значение UI / SharedPreferences — не сохранять в БД (в БД → `NULL`).
  static const unselected = '__UNSELECTED__';
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

bool isStoreLocationUnsetInDatabase(Map<String, dynamic> row) {
  final raw = row['store_location'];
  if (raw == null) return true;
  final text = raw.toString().trim();
  return text.isEmpty;
}

int _stockQuantity(Map<String, dynamic> row) {
  final raw = row['stock_quantity'];
  if (raw is num) return raw.toInt();
  return int.tryParse(raw?.toString().trim() ?? '') ?? 0;
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

/// Код для бейджа в таблице витрины / черновика (включая «не выбран»).
String storeLocationCodeFromProductRow(Map<String, dynamic> row) {
  if (isStoreLocationUnsetInDatabase(row)) {
    if (_stockQuantity(row) > 0) {
      return StoreLocationCode.icn;
    }
    return StoreLocationCode.unselected;
  }
  return normalizeStoreLocationCode(
    storeLocation: row['store_location']?.toString(),
    productRow: row,
  );
}

/// Код переключателя в форме (черновик: NULL → unselected; витрина: NULL → ICN).
String storeLocationPickerCodeFromRow(Map<String, dynamic> row) {
  if (isStoreLocationUnsetInDatabase(row)) {
    return _stockQuantity(row) > 0
        ? StoreLocationCode.icn
        : StoreLocationCode.unselected;
  }
  return normalizeStoreLocationCode(
    storeLocation: row['store_location']?.toString(),
    productRow: row,
  );
}

String storeLocationPickerCodeFromPrefs(String? stored) {
  final raw = stored?.trim() ?? '';
  if (raw.isEmpty) return StoreLocationCode.unselected;
  if (raw == StoreLocationCode.unselected) return StoreLocationCode.unselected;
  return normalizeStoreLocationCode(storeLocation: raw);
}

/// Значение для колонки `products.store_location` (`NULL` = не выбран).
String? storeLocationToDatabaseValue(String pickerCode) {
  if (pickerCode == StoreLocationCode.unselected) return null;
  return normalizeStoreLocationCode(storeLocation: pickerCode);
}

/// Циклическое переключение в приёмке черновиков.
String? cycleDraftStoreLocationPicker(String? currentDbCode) {
  final current = (currentDbCode == null || currentDbCode.trim().isEmpty)
      ? StoreLocationCode.unselected
      : normalizeStoreLocationCode(storeLocation: currentDbCode);
  switch (current) {
    case StoreLocationCode.unselected:
      return StoreLocationCode.icn;
    case StoreLocationCode.icn:
      return StoreLocationCode.ans;
    case StoreLocationCode.ans:
      return null;
    default:
      return null;
  }
}

String storeLocationDbCodeForCycleResult(String? code) {
  if (code == null) return StoreLocationCode.unselected;
  return normalizeStoreLocationCode(storeLocation: code);
}

/// Человекочитаемая подпись для админки.
String storeLocationDisplayLabel(
  String code, {
  String? originalMart,
}) {
  if (code == StoreLocationCode.unselected) return 'Не выбран';
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

/// Цвета бейджа: Инчхон — красный, Ансан — синий, не выбран — серый.
({Color bg, Color fg}) storeLocationBadgeColors(String code) {
  if (code == StoreLocationCode.unselected) {
    return (
      bg: const Color(0xFFF3F4F6),
      fg: const Color(0xFF6B7280),
    );
  }
  switch (code.toUpperCase()) {
    case StoreLocationCode.ans:
      return (
        bg: const Color(0xFFE8F0FE),
        fg: const Color(0xFF1A4FB8),
      );
    case StoreLocationCode.icn:
    default:
      return (
        bg: const Color(0xFFFEE2E2),
        fg: const Color(0xFFB91C1C),
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
    if (code == StoreLocationCode.unselected) continue;
    final prev = buckets[code] ?? const ShowroomStoreSelectionStats();
    buckets[code] = ShowroomStoreSelectionStats(
      count: prev.count + 1,
      weightGrams: prev.weightGrams + weightGramsForRow(row),
      priceKrw: prev.priceKrw + priceKrwForRow(row),
    );
  }
  return buckets;
}

/// Переключатель «Магазин (точка прихода)»: три состояния с цветовой кодировкой.
class StoreLocationTriStateSelector extends StatelessWidget {
  const StoreLocationTriStateSelector({
    super.key,
    required this.selectedCode,
    required this.onChanged,
    this.title = 'Магазин (точка прихода)',
  });

  final String selectedCode;
  final ValueChanged<String> onChanged;
  final String title;

  static const _options = [
    StoreLocationCode.unselected,
    StoreLocationCode.icn,
    StoreLocationCode.ans,
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _options.map((code) {
            final colors = storeLocationBadgeColors(code);
            final selected = selectedCode == code;
            final label = storeLocationDisplayLabel(code);
            return Material(
              color: selected ? colors.bg : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () => onChanged(code),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected
                          ? colors.fg
                          : colors.fg.withValues(alpha: 0.35),
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: colors.fg,
                      fontWeight:
                          selected ? FontWeight.w800 : FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

/// Кликабельный бейдж магазина (приёмка / таблица).
class StoreLocationClickableBadge extends StatelessWidget {
  const StoreLocationClickableBadge({
    super.key,
    required this.code,
    this.onTap,
    this.showCycleIcon = false,
    this.compact = false,
  });

  final String code;
  final VoidCallback? onTap;
  final bool showCycleIcon;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final label = storeLocationDisplayLabel(code);
    final colors = storeLocationBadgeColors(code);
    final child = Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: colors.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.fg.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.fg,
                fontWeight: FontWeight.w700,
                fontSize: compact ? 11 : 12,
              ),
            ),
          ),
          if (showCycleIcon && onTap != null) ...[
            const SizedBox(width: 4),
            Icon(
              Icons.swap_horiz,
              size: compact ? 12 : 14,
              color: colors.fg,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) return child;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: child,
    );
  }
}