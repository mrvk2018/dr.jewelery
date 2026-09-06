import '../../core/l10n/localized_text.dart';

export '../../core/utils/won_format.dart';

/// Демонстрационная модель ювелирного изделия с мультиязычными полями.
class ProductItem {
  const ProductItem({
    required this.id,
    required this.sku,
    required this.stockQuantity,
    required this.name,
    required this.description,
    required this.metal,
    required this.salePrice,
    required this.oldPrice,
    required this.discountPercent,
    required this.category,
    required this.insert,
    this.iconIndex = 0,
    this.availableSizes = const [],
  });

  final String id;
  /// Артикул / штрихкод кассовой системы (ключ синхронизации POS).
  final String sku;
  /// Текущий остаток на складе / в кассе.
  final int stockQuantity;
  /// Полные названия на ru/kk/ko/en/uz — не пословный перевод.
  final Map<String, String> name;
  /// Полные описания на ru/kk/ko/en/uz.
  final Map<String, String> description;
  final String metal;
  final int salePrice;
  final int oldPrice;
  final int discountPercent;
  final String category;
  final String insert;
  final int iconIndex;
  final List<double> availableSizes;

  bool get isOutOfStock => stockQuantity <= 0;

  Map<String, String> get nameTranslations => name;
  Map<String, String> get descriptionTranslations => description;

  String localizedName(String languageCode) =>
      LocalizedText.resolve(name, languageCode: languageCode);

  String localizedDescription(String languageCode) =>
      LocalizedText.resolve(description, languageCode: languageCode);

  Map<String, dynamic> toJson() => {
        'id': id,
        'sku': sku,
        'stockQuantity': stockQuantity,
        'name': name,
        'description': description,
        'metal': metal,
        'salePrice': salePrice,
        'oldPrice': oldPrice,
        'discountPercent': discountPercent,
        'category': category,
        'insert': insert,
        'iconIndex': iconIndex,
        'availableSizes': availableSizes,
      };

  factory ProductItem.fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    return ProductItem(
      id: id,
      sku: json['sku'] as String? ?? 'DJ-${id.padLeft(4, '0')}',
      stockQuantity: (json['stockQuantity'] as num?)?.toInt() ?? 8,
      name: Map<String, String>.from(json['name'] as Map),
      description: Map<String, String>.from(json['description'] as Map),
      metal: json['metal'] as String,
      salePrice: json['salePrice'] as int,
      oldPrice: json['oldPrice'] as int,
      discountPercent: json['discountPercent'] as int,
      category: json['category'] as String,
      insert: json['insert'] as String,
      iconIndex: json['iconIndex'] as int? ?? 0,
      availableSizes: (json['availableSizes'] as List<dynamic>? ?? const [])
          .map((size) => (size as num).toDouble())
          .toList(),
    );
  }

  ProductItem copyWith({
    String? id,
    String? sku,
    int? stockQuantity,
    Map<String, String>? name,
    Map<String, String>? description,
    String? metal,
    int? salePrice,
    int? oldPrice,
    int? discountPercent,
    String? category,
    String? insert,
    int? iconIndex,
    List<double>? availableSizes,
  }) {
    return ProductItem(
      id: id ?? this.id,
      sku: sku ?? this.sku,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      name: name ?? this.name,
      description: description ?? this.description,
      metal: metal ?? this.metal,
      salePrice: salePrice ?? this.salePrice,
      oldPrice: oldPrice ?? this.oldPrice,
      discountPercent: discountPercent ?? this.discountPercent,
      category: category ?? this.category,
      insert: insert ?? this.insert,
      iconIndex: iconIndex ?? this.iconIndex,
      availableSizes: availableSizes ?? this.availableSizes,
    );
  }
}

/// Рассчитывает старую цену по скидке для админ-формы.
int calculateOldPriceFromDiscount(int salePrice, int discountPercent) {
  if (discountPercent <= 0 || discountPercent >= 100) return salePrice;
  return (salePrice / (1 - discountPercent / 100)).round();
}

ProductItem _demoProduct({
  required String id,
  required String sku,
  required int stockQuantity,
  required String ruName,
  required String ruDescription,
  required String metal,
  required int salePrice,
  required int oldPrice,
  required int discountPercent,
  required String category,
  required String insert,
  int iconIndex = 0,
  List<double> availableSizes = const [],
}) {
  return ProductItem(
    id: id,
    sku: sku,
    stockQuantity: stockQuantity,
    name: demoLocalizedName(ruName),
    description: demoLocalizedDescription(ruDescription),
    metal: metal,
    salePrice: salePrice,
    oldPrice: oldPrice,
    discountPercent: discountPercent,
    category: category,
    insert: insert,
    iconIndex: iconIndex,
    availableSizes: availableSizes,
  );
}

/// Демонстрационный список товаров для главной и каталога.
final demoRecommendedProducts = <ProductItem>[
  _demoProduct(
    id: '1',
    sku: 'DJ-GOLD-001',
    stockQuantity: 4,
    ruName: 'Кольцо из белого золота с бриллиантом',
    ruDescription: 'Изысканное кольцо с бриллиантом огранки brilliant.',
    metal: 'Белое золото',
    salePrice: 890000,
    oldPrice: 2225000,
    discountPercent: 60,
    category: 'Кольца',
    insert: 'Бриллиант',
    availableSizes: [15, 15.5, 16, 16.5, 17],
  ),
  _demoProduct(
    id: '2',
    sku: 'DJ-EARR-002',
    stockQuantity: 7,
    ruName: 'Серьги с изумрудом',
    ruDescription: 'Элегантные серьги с натуральным изумрудом.',
    metal: 'Белое золото',
    salePrice: 1250000,
    oldPrice: 2841000,
    discountPercent: 56,
    iconIndex: 1,
    category: 'Серьги',
    insert: 'Изумруд',
  ),
  _demoProduct(
    id: '3',
    sku: 'DJ-PEND-003',
    stockQuantity: 12,
    ruName: 'Подвеска «Капля» с сапфиром',
    ruDescription: 'Подвеска каплевидной формы с сапфировой вставкой.',
    metal: 'Красное золото',
    salePrice: 450000,
    oldPrice: 938000,
    discountPercent: 52,
    iconIndex: 2,
    category: 'Подвески',
    insert: 'Сапфир',
  ),
  _demoProduct(
    id: '4',
    sku: 'DJ-BRAC-004',
    stockQuantity: 15,
    ruName: 'Браслет с фианитами',
    ruDescription: 'Изящный браслет с фианитами по всему периметру.',
    metal: 'Серебро',
    salePrice: 125000,
    oldPrice: 250000,
    discountPercent: 50,
    iconIndex: 3,
    category: 'Браслеты',
    insert: 'Топаз',
  ),
  _demoProduct(
    id: '5',
    sku: 'DJ-HEART-005',
    stockQuantity: 9,
    ruName: 'Подвеска «Сердце»',
    ruDescription: 'Романтичная подвеска в форме сердца.',
    metal: 'Красное золото',
    salePrice: 320000,
    oldPrice: 744000,
    discountPercent: 57,
    iconIndex: 4,
    category: 'Подвески',
    insert: 'Без вставок',
  ),
  _demoProduct(
    id: '6',
    sku: 'DJ-RING-006',
    stockQuantity: 3,
    ruName: 'Обручальное кольцо классическое',
    ruDescription: 'Классическое обручальное кольцо премиального качества.',
    metal: 'Платина',
    salePrice: 1500000,
    oldPrice: 3061000,
    discountPercent: 51,
    iconIndex: 5,
    category: 'Кольца',
    insert: 'Без вставок',
    availableSizes: [16, 16.5, 17, 17.5, 18],
  ),
  _demoProduct(
    id: '7',
    sku: 'DJ-WATCH-007',
    stockQuantity: 6,
    ruName: 'Часы «Dr. Jewelry Classic»',
    ruDescription: 'Премиальные часы коллекции Dr. Jewelry Classic.',
    metal: 'Белое золото',
    salePrice: 980000,
    oldPrice: 1885000,
    discountPercent: 48,
    iconIndex: 6,
    category: 'Часы',
    insert: 'Без вставок',
  ),
  _demoProduct(
    id: '8',
    sku: 'DJ-TOPAZ-008',
    stockQuantity: 11,
    ruName: 'Кольцо с топазом',
    ruDescription: 'Кольцо с яркой топазовой вставкой.',
    metal: 'Серебро',
    salePrice: 89000,
    oldPrice: 178000,
    discountPercent: 50,
    iconIndex: 0,
    category: 'Кольца',
    insert: 'Топаз',
    availableSizes: [15.5, 16, 16.5, 17],
  ),
];

/// Начальный ассортимент витрины (6 демо-товаров).
final initialCatalogProducts =
    List<ProductItem>.unmodifiable(demoRecommendedProducts.take(6));
