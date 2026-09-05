import '../../core/l10n/localized_text.dart';

/// Демонстрационная модель ювелирного изделия с мультиязычными полями.
class ProductItem {
  const ProductItem({
    required this.id,
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
  final Map<String, String> name;
  final Map<String, String> description;
  final String metal;
  final int salePrice;
  final int oldPrice;
  final int discountPercent;
  final String category;
  final String insert;
  final int iconIndex;
  final List<double> availableSizes;

  String localizedName(String languageCode) =>
      LocalizedText.resolve(name, languageCode: languageCode);

  String localizedDescription(String languageCode) =>
      LocalizedText.resolve(description, languageCode: languageCode);

  Map<String, dynamic> toJson() => {
        'id': id,
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
    return ProductItem(
      id: json['id'] as String,
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
}

/// Рассчитывает старую цену по скидке для админ-формы.
int calculateOldPriceFromDiscount(int salePrice, int discountPercent) {
  if (discountPercent <= 0 || discountPercent >= 100) return salePrice;
  return (salePrice / (1 - discountPercent / 100)).round();
}

/// Форматирует цену в рублях с пробелами: 14 990 ₽.
String formatRubPrice(int price) {
  final digits = price.toString();
  final buffer = StringBuffer();

  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(' ');
    }
    buffer.write(digits[i]);
  }

  return '${buffer.toString()} ₽';
}

ProductItem _demoProduct({
  required String id,
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
    ruName: 'Кольцо из белого золота с бриллиантом',
    ruDescription: 'Изысканное кольцо с бриллиантом огранки brilliant.',
    metal: 'Белое золото',
    salePrice: 14990,
    oldPrice: 37500,
    discountPercent: 60,
    category: 'Кольца',
    insert: 'Бриллиант',
    availableSizes: [15, 15.5, 16, 16.5, 17],
  ),
  _demoProduct(
    id: '2',
    ruName: 'Серьги с изумрудом',
    ruDescription: 'Элегантные серьги с натуральным изумрудом.',
    metal: 'Белое золото',
    salePrice: 22990,
    oldPrice: 52000,
    discountPercent: 56,
    iconIndex: 1,
    category: 'Серьги',
    insert: 'Изумруд',
  ),
  _demoProduct(
    id: '3',
    ruName: 'Подвеска «Капля» с сапфиром',
    ruDescription: 'Подвеска каплевидной формы с сапфировой вставкой.',
    metal: 'Красное золото',
    salePrice: 8990,
    oldPrice: 18900,
    discountPercent: 52,
    iconIndex: 2,
    category: 'Подвески',
    insert: 'Сапфир',
  ),
  _demoProduct(
    id: '4',
    ruName: 'Браслет с фианитами',
    ruDescription: 'Изящный браслет с фианитами по всему периметру.',
    metal: 'Серебро',
    salePrice: 4990,
    oldPrice: 9900,
    discountPercent: 50,
    iconIndex: 3,
    category: 'Браслеты',
    insert: 'Топаз',
  ),
  _demoProduct(
    id: '5',
    ruName: 'Подвеска «Сердце»',
    ruDescription: 'Романтичная подвеска в форме сердца.',
    metal: 'Красное золото',
    salePrice: 11990,
    oldPrice: 28000,
    discountPercent: 57,
    iconIndex: 4,
    category: 'Подвески',
    insert: 'Без вставок',
  ),
  _demoProduct(
    id: '6',
    ruName: 'Обручальное кольцо классическое',
    ruDescription: 'Классическое обручальное кольцо премиального качества.',
    metal: 'Платина',
    salePrice: 34990,
    oldPrice: 72000,
    discountPercent: 51,
    iconIndex: 5,
    category: 'Кольца',
    insert: 'Без вставок',
    availableSizes: [16, 16.5, 17, 17.5, 18],
  ),
  _demoProduct(
    id: '7',
    ruName: 'Часы «Sunlight Classic»',
    ruDescription: 'Премиальные часы коллекции Sunlight Classic.',
    metal: 'Белое золото',
    salePrice: 45990,
    oldPrice: 89000,
    discountPercent: 48,
    iconIndex: 6,
    category: 'Часы',
    insert: 'Без вставок',
  ),
  _demoProduct(
    id: '8',
    ruName: 'Кольцо с топазом',
    ruDescription: 'Кольцо с яркой топазовой вставкой.',
    metal: 'Серебро',
    salePrice: 6990,
    oldPrice: 13900,
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
