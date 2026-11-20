/// Справочник основных категорий и видов изделий (админ-форма, фильтр, RPC).
const String kJewelryCategoryOther = 'Другое';
const String kJewelrySubtypeUnspecified = '__unspecified__';
const String kJewelrySubtypeCustom = 'Свой вариант...';
const String kJewelryCategorySubtypeSeparator = ' · ';

const Map<String, List<String>> kJewelryCategorySubtypes = {
  'Серьги': [
    'декоративные',
    'с подвесной частью',
    'детские',
    'пусеты',
    'продёвки',
    'конго',
    'каффы',
    'одиночки',
  ],
  'Кольцо': [
    'обручальные',
    'печатки',
    'Спаси и сохрани',
    'декоративные',
  ],
  'Подвески': [
    'декоративные',
    'знаки зодиака',
    'православные',
    'мусульманские',
  ],
  'Крест': [
    'с распятием православный',
    'без распятия',
  ],
  'Колье': [
    'с подвижным элементом',
    'с фиксированным элементом',
    'на леске',
  ],
  'Цепь': [
    'полновесная',
    'облегчённая',
  ],
  'Браслет': [
    'штампованный',
    'цепевязальный',
    'с декоративным элементом',
    'красная нить',
  ],
  'Пирсинг': [
    'в ухо',
    'в пупок',
  ],
  'Гайтан': [
    'текстильный',
    'каучуковый',
  ],
  'Брошь': [
    'декоративная',
    'булавка',
  ],
};

/// 10 складских/витринных категорий + «Другое».
List<String> get kJewelryMainCategories => [
      ...kJewelryCategorySubtypes.keys,
      kJewelryCategoryOther,
    ];

final Set<String> _mainCategoryLookup = {
  for (final c in kJewelryCategorySubtypes.keys) c.toLowerCase(),
};

bool isKnownJewelryMainCategory(String value) {
  return _mainCategoryLookup.contains(value.trim().toLowerCase());
}

/// Пары «категория · вид» для чекбоксов в фильтре «Дополнительно».
List<JewelrySubtypeFilterOption> get kJewelrySubtypeFilterOptions {
  final options = <JewelrySubtypeFilterOption>[];
  for (final entry in kJewelryCategorySubtypes.entries) {
    for (final subtype in entry.value) {
      options.add(
        JewelrySubtypeFilterOption(
          category: entry.key,
          subtype: subtype,
          filterTag: subtype,
          label: '${entry.key}$kJewelryCategorySubtypeSeparator$subtype',
        ),
      );
    }
  }
  return options;
}

class JewelrySubtypeFilterOption {
  const JewelrySubtypeFilterOption({
    required this.category,
    required this.subtype,
    required this.filterTag,
    required this.label,
  });

  final String category;
  final String subtype;
  final String filterTag;
  final String label;
}

class ParsedJewelryProductCategory {
  const ParsedJewelryProductCategory({
    required this.mainCategory,
    this.catalogSubtype,
    this.customSubtype,
    required this.displayName,
    required this.isOther,
  });

  final String mainCategory;
  final String? catalogSubtype;
  final String? customSubtype;
  final String displayName;
  final bool isOther;
}

String formatJewelryProductDisplayName({
  required String mainCategory,
  String? subtype,
}) {
  final cat = mainCategory.trim();
  final sub = subtype?.trim() ?? '';
  if (cat.isEmpty) return '';
  if (sub.isEmpty) return cat;
  return '$cat$kJewelryCategorySubtypeSeparator$sub';
}

/// Подстроки для ILIKE / advanced_tags (пусеты: DrJaw «гвоздики», опечатка Latin c).
List<String> jewelrySubtypeAdvancedSearchTerms(String subtype) {
  final key = subtype.trim().toLowerCase();
  if (key.isEmpty) return const [];
  return switch (key) {
    'пусеты' => const ['пусеты', 'пусет', 'пуссет', 'гвозд'],
    'продёвки' => const ['продёвки', 'продёв', 'продев'],
    _ => [subtype.trim()],
  };
}

String? subtypeForCategory(String category, String subtypeOrCustom) {
  final list = kJewelryCategorySubtypes[category];
  if (list == null) return null;
  final lower = subtypeOrCustom.trim().toLowerCase();
  for (final item in list) {
    if (item.toLowerCase() == lower) return item;
  }
  return null;
}

/// Разбор `name` (+ fallback `category`) для формы редактирования.
ParsedJewelryProductCategory parseJewelryProductCategoryFromRow({
  required String? nameText,
  String? categoryColumn,
}) {
  var name = nameText?.trim() ?? '';
  final categoryRaw = categoryColumn?.trim() ?? '';

  if (name.isEmpty && categoryRaw.isNotEmpty) {
    name = categoryRaw;
  }

  if (name.isEmpty) {
    return const ParsedJewelryProductCategory(
      mainCategory: 'Кольцо',
      displayName: '',
      isOther: false,
    );
  }

  if (!name.contains(kJewelryCategorySubtypeSeparator)) {
    if (isKnownJewelryMainCategory(name)) {
      return ParsedJewelryProductCategory(
        mainCategory: _canonicalMainCategory(name),
        displayName: name,
        isOther: false,
      );
    }
    if (categoryRaw.isNotEmpty && isKnownJewelryMainCategory(categoryRaw)) {
      return ParsedJewelryProductCategory(
        mainCategory: _canonicalMainCategory(categoryRaw),
        displayName: name,
        isOther: false,
      );
    }
    return ParsedJewelryProductCategory(
      mainCategory: kJewelryCategoryOther,
      displayName: name,
      isOther: true,
    );
  }

  final parts = name.split(kJewelryCategorySubtypeSeparator);
  final catPart = parts.first.trim();
  final subPart = parts.sublist(1).join(kJewelryCategorySubtypeSeparator).trim();

  var main = isKnownJewelryMainCategory(catPart)
      ? _canonicalMainCategory(catPart)
      : (categoryRaw.isNotEmpty && isKnownJewelryMainCategory(categoryRaw)
          ? _canonicalMainCategory(categoryRaw)
          : kJewelryCategoryOther);

  if (main == kJewelryCategoryOther) {
    return ParsedJewelryProductCategory(
      mainCategory: kJewelryCategoryOther,
      displayName: name,
      isOther: true,
    );
  }

  final catalogSub = subtypeForCategory(main, subPart);
  if (catalogSub != null) {
    return ParsedJewelryProductCategory(
      mainCategory: main,
      catalogSubtype: catalogSub,
      displayName: name,
      isOther: false,
    );
  }

  return ParsedJewelryProductCategory(
    mainCategory: main,
    customSubtype: subPart,
    displayName: name,
    isOther: false,
  );
}

String _canonicalMainCategory(String value) {
  final lower = value.trim().toLowerCase();
  for (final key in kJewelryCategorySubtypes.keys) {
    if (key.toLowerCase() == lower) return key;
  }
  return value.trim();
}

/// Маппинг устаревших значений DrJaw / админки к основной категории.
String normalizeWarehouseCategoryToMain(String? raw) {
  final c = raw?.trim() ?? '';
  if (c.isEmpty) return '';
  final lower = c.toLowerCase();
  if (lower == 'подвеска' || lower == 'подвески') return 'Подвески';
  if (isKnownJewelryMainCategory(c)) return _canonicalMainCategory(c);
  return c;
}