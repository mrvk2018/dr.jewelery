import '../../catalog/domain/models/catalog_constants.dart';
import '../../catalog/domain/utils/catalog_metal_facet_utils.dart';

enum DraftMetalBatchGroup { gold, silver, other }

/// Сводка по одной металлической группе черновиков.
class DraftBatchGroupTotals {
  const DraftBatchGroupTotals({
    this.count = 0,
    this.weightGrams = 0,
    this.priceKrw = 0,
  });

  final int count;
  final double weightGrams;
  final int priceKrw;

  DraftBatchGroupTotals accumulate({
    required double weightGrams,
    required int priceKrw,
  }) {
    return DraftBatchGroupTotals(
      count: count + 1,
      weightGrams: this.weightGrams + weightGrams,
      priceKrw: this.priceKrw + priceKrw,
    );
  }

  DraftBatchGroupTotals operator +(DraftBatchGroupTotals other) {
    return DraftBatchGroupTotals(
      count: count + other.count,
      weightGrams: weightGrams + other.weightGrams,
      priceKrw: priceKrw + other.priceKrw,
    );
  }
}

class DraftBatchReconcileReport {
  const DraftBatchReconcileReport({
    required this.gold,
    required this.silver,
    required this.other,
  });

  final DraftBatchGroupTotals gold;
  final DraftBatchGroupTotals silver;
  final DraftBatchGroupTotals other;

  DraftBatchGroupTotals get grandTotal => gold + silver + other;
}

final _goldFacetPatterns = metalFacetLabelsToIlikePatterns({
  CatalogMetals.gold,
  CatalogMetals.redGold,
  CatalogMetals.yellowGold,
  CatalogMetals.whiteGold,
});

final _silverFacetPatterns = metalFacetLabelsToIlikePatterns({
  CatalogMetals.silver,
});

bool _haystackMatchesFacetPatterns(String haystack, List<String> patterns) {
  if (haystack.isEmpty) return false;
  final lower = haystack.toLowerCase();
  for (final pattern in patterns) {
    final core = pattern.replaceAll('%', '').toLowerCase();
    if (core.isNotEmpty && lower.contains(core)) return true;
  }
  return false;
}

/// Та же семантика, что фасеты витрины (`showroom_metal_facet_match` / SmartFilter).
DraftMetalBatchGroup classifyDraftMetalBatchGroup(Map<String, dynamic> row) {
  final metal = (row['metal_type'] ?? row['metal'])?.toString().trim() ?? '';
  if (metal.isEmpty || metal == '—') {
    return DraftMetalBatchGroup.other;
  }

  final lower = metal.toLowerCase();
  if (lower.contains('родирован') ||
      RegExp(r'\b925\b', caseSensitive: false).hasMatch(metal) ||
      RegExp(r'\bag\d*', caseSensitive: false).hasMatch(metal)) {
    return DraftMetalBatchGroup.silver;
  }
  if (RegExp(r'(375|583|585|750|999)', caseSensitive: false).hasMatch(metal) ||
      RegExp(r'\bau\d*', caseSensitive: false).hasMatch(metal)) {
    return DraftMetalBatchGroup.gold;
  }

  if (_haystackMatchesFacetPatterns(metal, _silverFacetPatterns)) {
    return DraftMetalBatchGroup.silver;
  }
  if (_haystackMatchesFacetPatterns(metal, _goldFacetPatterns)) {
    return DraftMetalBatchGroup.gold;
  }

  if (lower.contains('silver')) {
    return DraftMetalBatchGroup.silver;
  }
  if (lower.contains('gold') || lower.contains('золот')) {
    return DraftMetalBatchGroup.gold;
  }
  if (lower.contains('серебр')) {
    return DraftMetalBatchGroup.silver;
  }

  return DraftMetalBatchGroup.other;
}

DraftBatchReconcileReport computeDraftBatchReconcileReport(
  List<Map<String, dynamic>> rows, {
  required double Function(Map<String, dynamic>) weightGramsForRow,
  required int Function(Map<String, dynamic>) priceKrwForRow,
}) {
  var gold = const DraftBatchGroupTotals();
  var silver = const DraftBatchGroupTotals();
  var other = const DraftBatchGroupTotals();

  for (final row in rows) {
    final weight = weightGramsForRow(row);
    final price = priceKrwForRow(row);
    final bucket = classifyDraftMetalBatchGroup(row);
    switch (bucket) {
      case DraftMetalBatchGroup.gold:
        gold = gold.accumulate(weightGrams: weight, priceKrw: price);
      case DraftMetalBatchGroup.silver:
        silver = silver.accumulate(weightGrams: weight, priceKrw: price);
      case DraftMetalBatchGroup.other:
        other = other.accumulate(weightGrams: weight, priceKrw: price);
    }
  }

  return DraftBatchReconcileReport(gold: gold, silver: silver, other: other);
}

String formatDraftReconcileKrw(int krw) {
  final spaced = krw.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]} ',
  );
  return '$spaced ₩';
}

String draftBatchReconcilePlainText({
  required DraftBatchReconcileReport report,
  required String scopeSubtitle,
  required int totalRows,
}) {
  final buffer = StringBuffer()
    ..writeln('Сверка партии черновиков')
    ..writeln(scopeSubtitle)
    ..writeln('Позиций в списке: $totalRows')
    ..writeln();

  void block(String title, DraftBatchGroupTotals stats) {
    buffer
      ..writeln(title)
      ..writeln('  Количество: ${stats.count} шт.')
      ..writeln('  Масса: ${stats.weightGrams.toStringAsFixed(2)} г')
      ..writeln('  Сумма: ${formatDraftReconcileKrw(stats.priceKrw)}')
      ..writeln();
  }

  block('Золото', report.gold);
  block('Серебро', report.silver);
  if (report.other.count > 0) {
    block('Прочее / Не указано', report.other);
  }

  final g = report.grandTotal;
  buffer
    ..writeln('ИТОГО')
    ..writeln('  Количество: ${g.count} шт.')
    ..writeln('  Масса: ${g.weightGrams.toStringAsFixed(2)} г')
    ..writeln('  Сумма: ${formatDraftReconcileKrw(g.priceKrw)}');

  return buffer.toString();
}