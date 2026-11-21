/// Справочник основных категорий и видов изделий (админ-форма, фильтр, RPC).
const String kJewelryCategoryOther = 'Другое';
const String kJewelrySubtypeUnspecified = '__unspecified__';
const String kJewelrySubtypeCustom = 'Свой вариант...';
const String kJewelryCategorySubtypeSeparator = ' · ';

/// Категория «Подвеска» в формах; чип витрины остаётся [kJewelryShowroomCategoryPendantsCollective].
const String kJewelryShowroomCategoryPendantsCollective = 'Подвески';

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
    'обручальное',
    'помолвочное',
    'печатка',
    'Спаси и сохрани',
    'декоративное',
  ],
  'Подвеска': [
    'декоративная',
    'знак зодиака',
    'православная',
    'мусульманская',
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

/// Устаревшие названия категорий (форма / БД) → канон для dropdown.
const Map<String, String> kLegacyMainCategoryAliases = {
  'подвески': 'Подвеска',
};

/// Устаревшие подвиды (мн.ч. / старая разметка) → канон для dropdown.
const Map<String, Map<String, String>> kLegacySubtypeAliases = {
  'Кольцо': {
    'обручальные': 'обручальное',
    'помолвочные': 'помолвочное',
    'печатки': 'печатка',
    'декоративные': 'декоративное',
  },
  'Подвеска': {
    'декоративные': 'декоративная',
    'знаки зодиака': 'знак зодиака',
    'православные': 'православная',
    'мусульманские': 'мусульманская',
  },
};

/// 10 складских/витринных категорий + «Другое».
List<String> get kJewelryMainCategories => [
      ...kJewelryCategorySubtypes.keys,
      kJewelryCategoryOther,
    ];

final Set<String> _mainCategoryLookup = {
  for (final c in kJewelryCategorySubtypes.keys) c.toLowerCase(),
  ...kLegacyMainCategoryAliases.keys,
};

bool isKnownJewelryMainCategory(String value) {
  return _mainCategoryLookup.contains(value.trim().toLowerCase());
}

/// Каноническое имя категории для форм и записи в БД.
String canonicalJewelryMainCategory(String value) {
  final lower = value.trim().toLowerCase();
  final legacy = kLegacyMainCategoryAliases[lower];
  if (legacy != null) return legacy;
  for (final key in kJewelryCategorySubtypes.keys) {
    if (key.toLowerCase() == lower) return key;
  }
  return value.trim();
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
  final cat = canonicalJewelryMainCategory(mainCategory);
  final sub = subtype?.trim() ?? '';
  if (cat.isEmpty) return '';
  if (sub.isEmpty) return cat;
  return '$cat$kJewelryCategorySubtypeSeparator$sub';
}

/// Подстроки для ILIKE / advanced_tags (плюс основы для legacy мн.ч.).
List<String> jewelrySubtypeAdvancedSearchTerms(String subtype) {
  final key = subtype.trim().toLowerCase();
  if (key.isEmpty) return const [];
  return switch (key) {
    'пусеты' => const ['пусеты', 'пусет', 'пуссет', 'гвозд'],
    'продёвки' => const ['продёвки', 'продёв', 'продев'],
    'обручальное' =>
      const ['обручальное', 'обручальные', 'обручальн'],
    'помолвочное' =>
      const ['помолвочное', 'помолвочные', 'помолвочн'],
    'печатка' => const ['печатка', 'печатки', 'печатк'],
    'декоративное' =>
      const ['декоративное', 'декоративные', 'декоративн'],
    'декоративная' =>
      const ['декоративная', 'декоративные', 'декоративн'],
    'декоративные' => const ['декоративные', 'декоративн'],
    'знак зодиака' => const ['знак зодиака', 'знаки зодиака', 'зодиак'],
    'православная' =>
      const ['православная', 'православные', 'православн'],
    'мусульманская' =>
      const ['мусульманская', 'мусульманские', 'мусульманск'],
    _ => [subtype.trim()],
  };
}

String? _legacySubtypeForCategory(String mainCategory, String lowerSub) {
  final map = kLegacySubtypeAliases[mainCategory];
  return map?[lowerSub];
}

String? subtypeForCategory(String category, String subtypeOrCustom) {
  final main = canonicalJewelryMainCategory(category);
  final list = kJewelryCategorySubtypes[main];
  if (list == null) return null;
  final lower = subtypeOrCustom.trim().toLowerCase();
  for (final item in list) {
    if (item.toLowerCase() == lower) return item;
  }
  return _legacySubtypeForCategory(main, lower);
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
        mainCategory: canonicalJewelryMainCategory(name),
        displayName: canonicalJewelryMainCategory(name),
        isOther: false,
      );
    }
    if (categoryRaw.isNotEmpty && isKnownJewelryMainCategory(categoryRaw)) {
      return ParsedJewelryProductCategory(
        mainCategory: canonicalJewelryMainCategory(categoryRaw),
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
      ? canonicalJewelryMainCategory(catPart)
      : (categoryRaw.isNotEmpty && isKnownJewelryMainCategory(categoryRaw)
          ? canonicalJewelryMainCategory(categoryRaw)
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
      displayName: formatJewelryProductDisplayName(
        mainCategory: main,
        subtype: catalogSub,
      ),
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

/// Маппинг устаревших значений DrJaw / админки к основной категории.
String normalizeWarehouseCategoryToMain(String? raw) {
  final c = raw?.trim() ?? '';
  if (c.isEmpty) return '';
  if (isKnownJewelryMainCategory(c)) {
    return canonicalJewelryMainCategory(c);
  }
  return c;
}