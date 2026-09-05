import '../../../../core/l10n/localized_text.dart';

/// Товар в админ-панели с мультиязычными названием и описанием.
class AdminCatalogItem {
  AdminCatalogItem({
    required this.id,
    required Map<String, String> name,
    required Map<String, String> description,
    required this.price,
    required this.discountPercent,
    required this.category,
    this.photoLabel = 'Фото не выбрано',
  })  : name = Map<String, String>.from(name),
        description = Map<String, String>.from(description);

  final String id;
  Map<String, String> name;
  Map<String, String> description;
  int price;
  int discountPercent;
  String category;
  String photoLabel;

  String localizedName(String languageCode) =>
      LocalizedText.resolve(name, languageCode: languageCode);

  String localizedDescription(String languageCode) =>
      LocalizedText.resolve(description, languageCode: languageCode);

  AdminCatalogItem copyWith({
    Map<String, String>? name,
    Map<String, String>? description,
    int? price,
    int? discountPercent,
    String? category,
    String? photoLabel,
  }) {
    return AdminCatalogItem(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      discountPercent: discountPercent ?? this.discountPercent,
      category: category ?? this.category,
      photoLabel: photoLabel ?? this.photoLabel,
    );
  }
}

List<AdminCatalogItem> createDefaultAdminCatalog() {
  return [
    AdminCatalogItem(
      id: 'adm-1',
      name: demoLocalizedName('Кольцо из белого золота с бриллиантом'),
      description: demoLocalizedDescription(
        'Изысканное кольцо с бриллиантом огранки brilliant.',
      ),
      price: 14990,
      discountPercent: 60,
      category: 'Кольца',
      photoLabel: 'ring_diamond.jpg',
    ),
    AdminCatalogItem(
      id: 'adm-2',
      name: demoLocalizedName('Серьги с изумрудом'),
      description: demoLocalizedDescription(
        'Элегантные серьги с натуральным изумрудом.',
      ),
      price: 22990,
      discountPercent: 56,
      category: 'Серьги',
      photoLabel: 'earrings_emerald.jpg',
    ),
    AdminCatalogItem(
      id: 'adm-3',
      name: demoLocalizedName('Подвеска «Сердце»'),
      description: demoLocalizedDescription(
        'Романтичная подвеска в форме сердца.',
      ),
      price: 11990,
      discountPercent: 57,
      category: 'Подвески',
      photoLabel: 'pendant_heart.jpg',
    ),
  ];
}
