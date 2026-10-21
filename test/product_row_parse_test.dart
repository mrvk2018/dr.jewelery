import 'package:flutter_test/flutter_test.dart';
import 'package:jewelry_sunlight_store/shared/models/product_item.dart';

/// Минимальная строка, как приходит из Supabase после складского sync.
Map<String, dynamic> warehouseRowToClientJson(Map<String, dynamic> row) {
  final salePrice = (row['sale_price'] as num?)?.toInt() ?? 0;
  final oldPrice = (row['old_price'] as num?)?.toInt() ?? salePrice;
  return {
    'id': row['id']?.toString() ?? '',
    'sku': row['sku']?.toString() ?? '',
    'stockQuantity': (row['stock_quantity'] as num?)?.toInt() ?? 0,
    'name': row['name'] is Map ? row['name'] : <String, String>{},
    'description':
        row['description'] is Map ? row['description'] : <String, String>{},
    'metal': (row['metal'] as String?)?.trim() ?? '',
    'salePrice': salePrice,
    'oldPrice': oldPrice,
    'discountPercent': (row['discount_percent'] as num?)?.toInt() ?? 0,
    'category': (row['category'] as String?)?.trim() ?? '',
    'insert': (row['insert'] as String?)?.trim() ?? '',
    'iconIndex': (row['icon_index'] as num?)?.toInt() ?? 0,
    'availableSizes': row['available_sizes'] is List
        ? row['available_sizes']
        : const <dynamic>[],
    'imageUrl': row['image_url'] as String?,
    'images': row['images'] as List<dynamic>?,
    'weightGrams': (row['weight_grams'] as num?)?.toDouble(),
  };
}

void main() {
  test('parses sparse Supabase product row', () {
    final row = {
      'id': '16766',
      'sku': '011-0003',
      'stock_quantity': 1,
      'sale_price': 65000,
      'name': {
        'ru': '011-0003',
        'en': '011-0003',
      },
      'description': null,
      'metal': null,
      'insert': null,
      'category': null,
      'old_price': null,
      'discount_percent': null,
      'icon_index': null,
      'available_sizes': [],
      'image_url': null,
      'weight_grams': null,
      'status': 'active',
    };

    final item = ProductItem.fromJson(warehouseRowToClientJson(row));
    expect(item.id, '16766');
    expect(item.salePrice, 65000);
    expect(item.localizedName('ru'), '011-0003');
  });

  test('reads up to four images from Supabase row', () {
    final urls = List.generate(
      4,
      (i) => 'https://cdn.example/products/sku${i == 0 ? '' : '_$i'}.webp',
    );
    final row = {
      'id': '2',
      'sku': 'SKU-4',
      'stock_quantity': 1,
      'sale_price': 100,
      'name': {'ru': 'test'},
      'images': urls,
      'image_url': urls.first,
    };
    final item = ProductItem.fromJson(warehouseRowToClientJson(row));
    expect(item.images.length, 4);
    expect(item.imageUrl, urls.first);
  });

  test('storageGalleryUrlsFromBase expands webp slots', () {
    const base =
        'https://xxx.supabase.co/storage/v1/object/public/product-images/products/011-0003.webp?v=1';
    final urls = ProductItem.storageGalleryUrlsFromBase(base);
    expect(urls.length, ProductItem.maxGalleryImages);
    expect(urls[0], base);
    expect(urls[1], contains('011-0003_1.webp'));
    expect(urls[3], contains('011-0003_3.webp'));
  });
}
