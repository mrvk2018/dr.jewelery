/// Категории быстрого выбора в каталоге.
abstract final class CatalogCategories {
  static const all = 'Все';
  static const rings = 'Кольца';
  static const earrings = 'Серьги';
  static const pendants = 'Подвески';
  static const bracelets = 'Браслеты';
  static const watches = 'Часы';

  static const List<String> items = [
    rings,
    earrings,
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

/// Варианты металла для фильтра.
abstract final class CatalogMetals {
  static const redGold = 'Красное золото';
  static const whiteGold = 'Белое золото';
  static const silver = 'Серебро';
  static const platinum = 'Платина';

  static const List<String> items = [
    redGold,
    whiteGold,
    silver,
    platinum,
  ];
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
    this.selectedSize,
    this.selectedMetals = const {},
    this.selectedInserts = const {},
  });

  final double? selectedSize;
  final Set<String> selectedMetals;
  final Set<String> selectedInserts;

  CatalogFilterState copyWith({
    double? selectedSize,
    bool clearSize = false,
    Set<String>? selectedMetals,
    Set<String>? selectedInserts,
  }) {
    return CatalogFilterState(
      selectedSize: clearSize ? null : (selectedSize ?? this.selectedSize),
      selectedMetals: selectedMetals ?? this.selectedMetals,
      selectedInserts: selectedInserts ?? this.selectedInserts,
    );
  }

  bool get hasActiveFilters =>
      selectedSize != null ||
      selectedMetals.isNotEmpty ||
      selectedInserts.isNotEmpty;

  int get activeCount {
    var count = 0;
    if (selectedSize != null) count++;
    count += selectedMetals.length;
    count += selectedInserts.length;
    return count;
  }
}
