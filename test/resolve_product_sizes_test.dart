import 'package:flutter_test/flutter_test.dart';
import 'package:jewelry_sunlight_store/features/product/presentation/widgets/product_size_selector.dart';
import 'package:jewelry_sunlight_store/shared/models/product_item.dart';

ProductItem _ring({
  required String category,
  List<double> availableSizes = const [],
}) {
  return ProductItem(
    id: '1',
    sku: 'SKU-1',
    stockQuantity: 1,
    name: const {'ru': 'Test'},
    description: const {'ru': 'Test'},
    metal: 'Золото',
    salePrice: 1000,
    oldPrice: 1000,
    discountPercent: 0,
    category: category,
    insert: '—',
    availableSizes: availableSizes,
  );
}

void main() {
  test('resolveProductSizes accepts Кольцо and Кольца', () {
    expect(
      resolveProductSizes(_ring(category: 'Кольцо', availableSizes: [17.5])),
      [17.5],
    );
    expect(
      resolveProductSizes(_ring(category: 'Кольца', availableSizes: [15])),
      [15],
    );
    expect(resolveProductSizes(_ring(category: 'Серьги', availableSizes: [17])),
        isEmpty);
  });

  test('resolveProductSizes keeps warehouse sizes without whitelist filter', () {
    expect(
      resolveProductSizes(_ring(category: 'Кольцо', availableSizes: [18.5, 15])),
      [15, 18.5],
    );
  });

  test('defaultSelectedProductSize picks single warehouse size', () {
    final product = _ring(category: 'Кольцо', availableSizes: [17.5]);
    expect(defaultSelectedProductSize(product), 17.5);
  });

  test('ProductItem.fromJson parses string sizes safely', () {
    final item = ProductItem.fromJson({
      'id': '2',
      'category': 'Кольцо',
      'availableSizes': ['17', 'bad', 18.5],
    });
    expect(item.availableSizes, [17, 18.5]);
  });
}
