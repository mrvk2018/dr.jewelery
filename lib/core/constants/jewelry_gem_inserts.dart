/// Единый справочник вставок (админ-форма, фильтр «Дополнительно», RPC).
const String kJewelryGemInsertNone = 'Без вставок';

const List<String> kJewelryGemInserts = [
  kJewelryGemInsertNone,
  'Фианит',
  'Топаз Sky Blue',
  'Топаз Swiss Blue',
  'Топаз London Blue',
  'Раухтопаз',
  'Гранат',
  'Аметист',
  'Цитрин',
  'Оникс',
  'Наношпинель',
  'Эмаль',
  'Горный хрусталь',
  'Сапфир натуральный',
  'Сапфир Г/Т',
  'Изумруд натуральный',
  'Изумруд Г/Т',
  'Рубин натуральный',
  'Рубин Г/Т',
  'Александрит',
  'Бриллиант натуральный',
  'Бриллиант лабораторный',
  'Муассанит',
  'Агат',
  'Родолит',
  'Перламутр',
  'Кристалл Swarovski',
  'Жемчуг натуральный',
  'Жемчуг культивированный',
  'Янтарь',
  'Ситалл',
  'Малахит',
];

final Set<String> _catalogLookup = {
  for (final label in kJewelryGemInserts) label.toLowerCase(),
};

/// Результат разбора строки `insert` / `gem_inserts` из БД.
class ParsedGemInserts {
  const ParsedGemInserts({
    required this.catalog,
    required this.legacy,
  });

  final Set<String> catalog;
  final Set<String> legacy;
}

/// Нормализует фрагмент со склада к пункту справочника.
String? normalizeGemInsertToken(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final lower = trimmed.toLowerCase();
  if (lower == 'без камней' || lower == 'без вставок') {
    return kJewelryGemInsertNone;
  }
  for (final item in kJewelryGemInserts) {
    if (item.toLowerCase() == lower) return item;
  }
  return null;
}

ParsedGemInserts parseGemInsertsFromProductField(Object? raw) {
  final text = raw?.toString().trim() ?? '';
  if (text.isEmpty) {
    return const ParsedGemInserts(catalog: {}, legacy: {});
  }

  final catalog = <String>{};
  final legacy = <String>{};

  final whole = normalizeGemInsertToken(text);
  if (whole != null && !text.contains(',')) {
    catalog.add(whole);
    return ParsedGemInserts(catalog: catalog, legacy: legacy);
  }

  for (final part in text.split(',')) {
    final piece = part.trim();
    if (piece.isEmpty) continue;
    final normalized = normalizeGemInsertToken(piece);
    if (normalized != null) {
      catalog.add(normalized);
    } else {
      legacy.add(piece);
    }
  }

  if (catalog.contains(kJewelryGemInsertNone) && catalog.length > 1) {
    catalog.remove(kJewelryGemInsertNone);
  }

  return ParsedGemInserts(catalog: catalog, legacy: legacy);
}

String formatGemInsertsForStorage({
  required Set<String> catalog,
  Iterable<String> legacy = const [],
}) {
  final parts = <String>[];
  for (final item in kJewelryGemInserts) {
    if (catalog.contains(item)) parts.add(item);
  }
  for (final extra in legacy) {
    final t = extra.trim();
    if (t.isEmpty) continue;
    if (!parts.any((p) => p.toLowerCase() == t.toLowerCase())) {
      parts.add(t);
    }
  }
  return parts.join(', ');
}

String gemInsertsFieldHint(Set<String> catalog, Iterable<String> legacy) {
  final formatted = formatGemInsertsForStorage(catalog: catalog, legacy: legacy);
  return formatted.isEmpty ? 'Выберите вставки' : formatted;
}

/// Переключение пункта с правилом «Без вставок» exclusive.
void toggleJewelryGemInsert(Set<String> catalog, String label) {
  if (label == kJewelryGemInsertNone) {
    if (catalog.contains(kJewelryGemInsertNone)) {
      catalog.remove(kJewelryGemInsertNone);
    } else {
      catalog
        ..clear()
        ..add(kJewelryGemInsertNone);
    }
    return;
  }

  catalog.remove(kJewelryGemInsertNone);
  if (catalog.contains(label)) {
    catalog.remove(label);
  } else {
    catalog.add(label);
  }
}

bool isKnownJewelryGemCatalogLabel(String word) {
  return _catalogLookup.contains(word.trim().toLowerCase());
}