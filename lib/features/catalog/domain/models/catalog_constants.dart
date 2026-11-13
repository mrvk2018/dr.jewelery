/// Категории быстрого выбора в каталоге.
abstract final class CatalogCategories {
  static const all = 'Все';
  static const rings = 'Кольца';
  static const earrings = 'Серьги';
  static const chains = 'Цепи';
  static const pendants = 'Подвески';
  static const bracelets = 'Браслеты';
  static const watches = 'Часы';

  static const List<String> items = [
    rings,
    earrings,
    chains,
    pendants,
    bracelets,
    watches,
  ];
}

/// Доступные размеры колец для фильтра.
abstract final class CatalogRingSizes {
  static const List<double> items = [
    15,
    15.5,
    16,
    16.5,
    17,
    17.5,
    18,
  ];
}

/// Варианты металла для фильтра (фасеты витрины).
abstract final class CatalogMetals {
  static const gold = 'Золото';
  static const redGold = 'Красное золото';
  static const yellowGold = 'Жёлтое золото';
  static const whiteGold = 'Белое золото';
  static const silver = 'Серебро';
  static const platinum = 'Платина';

  static const List<String> items = [
    gold,
    redGold,
    yellowGold,
    whiteGold,
    silver,
  ];
}

/// Семейство металла (десктоп-сайдбар).
abstract final class CatalogMetalFamilies {
  static const gold = 'Золото';
  static const platinum = 'Платина';
  static const silver = 'Серебро';

  static const List<String> items = [gold, platinum, silver];
}

/// Пробы / маркировка для клиентского фильтра (подстрока в metal / sku).
abstract final class CatalogFineness {
  static const List<String> items = ['585', '750', '999', '925'];
}

/// Дефолтные границы слайдеров (каталог, ₩ и граммы).
abstract final class CatalogDesktopFilterBounds {
  static const int priceMinKrw = 0;
  static const int priceMaxKrw = 50000000;
  static const double weightMinGrams = 0;
  static const double weightMaxGrams = 100;
}

/// Варианты вставок для фильтра.
abstract final class CatalogInserts {
  static const diamond = 'Бриллиант';
  static const emerald = 'Изумруд';
  static const sapphire = 'Сапфир';
  static const topaz = 'Топаз';
  static const none = 'Без вставок';

  static const List<String> items = [
    diamond,
    emerald,
    sapphire,
    topaz,
    none,
  ];
}

/// Состояние фильтров каталога.
class CatalogFilterState {
  const CatalogFilterState({
    this.selectedSizes = const {},
    this.selectedMetals = const {},
    this.selectedInserts = const {},
    this.selectedCategories = const {},
    this.selectedMetalFamilies = const {},
    this.selectedFineness = const {},
    this.localSearchQuery = '',
    this.priceMinKrw = CatalogDesktopFilterBounds.priceMinKrw,
    this.priceMaxKrw = CatalogDesktopFilterBounds.priceMaxKrw,
    this.weightMinGrams = CatalogDesktopFilterBounds.weightMinGrams,
    this.weightMaxGrams = CatalogDesktopFilterBounds.weightMaxGrams,
  });

  final Set<double> selectedSizes;
  final Set<String> selectedMetals;
  final Set<String> selectedInserts;
  final Set<String> selectedCategories;
  final Set<String> selectedMetalFamilies;
  final Set<String> selectedFineness;
  final String localSearchQuery;
  final int priceMinKrw;
  final int priceMaxKrw;
  final double weightMinGrams;
  final double weightMaxGrams;

  CatalogFilterState copyWith({
    Set<double>? selectedSizes,
    Set<String>? selectedMetals,
    Set<String>? selectedInserts,
    Set<String>? selectedCategories,
    Set<String>? selectedMetalFamilies,
    Set<String>? selectedFineness,
    String? localSearchQuery,
    int? priceMinKrw,
    int? priceMaxKrw,
    double? weightMinGrams,
    double? weightMaxGrams,
  }) {
    return CatalogFilterState(
      selectedSizes: selectedSizes ?? this.selectedSizes,
      selectedMetals: selectedMetals ?? this.selectedMetals,
      selectedInserts: selectedInserts ?? this.selectedInserts,
      selectedCategories: selectedCategories ?? this.selectedCategories,
      selectedMetalFamilies: selectedMetalFamilies ?? this.selectedMetalFamilies,
      selectedFineness: selectedFineness ?? this.selectedFineness,
      localSearchQuery: localSearchQuery ?? this.localSearchQuery,
      priceMinKrw: priceMinKrw ?? this.priceMinKrw,
      priceMaxKrw: priceMaxKrw ?? this.priceMaxKrw,
      weightMinGrams: weightMinGrams ?? this.weightMinGrams,
      weightMaxGrams: weightMaxGrams ?? this.weightMaxGrams,
    );
  }

  bool get hasActiveFilters =>
      selectedSizes.isNotEmpty ||
      selectedMetals.isNotEmpty ||
      selectedInserts.isNotEmpty ||
      selectedCategories.isNotEmpty ||
      selectedMetalFamilies.isNotEmpty ||
      selectedFineness.isNotEmpty ||
      localSearchQuery.trim().isNotEmpty ||
      priceMinKrw > CatalogDesktopFilterBounds.priceMinKrw ||
      priceMaxKrw < CatalogDesktopFilterBounds.priceMaxKrw ||
      weightMinGrams > CatalogDesktopFilterBounds.weightMinGrams ||
      weightMaxGrams < CatalogDesktopFilterBounds.weightMaxGrams;

  int get activeCount {
    var n = selectedSizes.length +
        selectedMetals.length +
        selectedInserts.length +
        selectedCategories.length +
        selectedMetalFamilies.length +
        selectedFineness.length;
    if (localSearchQuery.trim().isNotEmpty) n++;
    if (priceMinKrw > CatalogDesktopFilterBounds.priceMinKrw ||
        priceMaxKrw < CatalogDesktopFilterBounds.priceMaxKrw) {
      n++;
    }
    if (weightMinGrams > CatalogDesktopFilterBounds.weightMinGrams ||
        weightMaxGrams < CatalogDesktopFilterBounds.weightMaxGrams) {
      n++;
    }
    return n;
  }

  List<String> get sizeTokens =>
      selectedSizes.map((s) => s.toString()).toList();

  /// Слайдеры цены/веса — только клиент (60 FPS).
  CatalogFilterState get clientBrowseSlice => CatalogFilterState(
        priceMinKrw: priceMinKrw,
        priceMaxKrw: priceMaxKrw,
        weightMinGrams: weightMinGrams,
        weightMaxGrams: weightMaxGrams,
      );

  /// Превью до «Применить»: поиск / семейство / проба на уже загруженной странице.
  CatalogFilterState get clientPreviewSlice => CatalogFilterState(
        localSearchQuery: localSearchQuery,
        selectedMetalFamilies: selectedMetalFamilies,
        selectedFineness: selectedFineness,
      );
}

