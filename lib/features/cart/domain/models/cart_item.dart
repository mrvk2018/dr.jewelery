import '../../../../shared/models/product_item.dart';

/// Позиция локальной корзины (SKU + размер = уникальная строка).
class CartItem {
  CartItem({
    required this.id,
    required this.productId,
    this.selectedSize,
    this.quantity = 1,
    this.product,
    this.isUnavailable = false,
  });

  final String id;
  final String productId;
  final String? selectedSize;
  int quantity;
  ProductItem? product;
  bool isUnavailable;

  /// Совместимость с прежним API (`cartKey`).
  String get cartKey => id;

  double? get selectedSizeAsDouble {
    final raw = selectedSize?.trim();
    if (raw == null || raw.isEmpty) return null;
    return double.tryParse(raw.replaceAll(',', '.'));
  }

  int get lineTotal => (product?.salePrice ?? 0) * quantity;

  int get lineOriginalTotal => (product?.oldPrice ?? 0) * quantity;

  /// Snapshot для UI/checkout (после add/load всегда задан).
  ProductItem get loadedProduct {
    final data = product;
    if (data == null) {
      throw StateError('Cart item $id is missing product snapshot');
    }
    return data;
  }

  static String? normalizeSize(String? size) {
    final trimmed = size?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  static String composeId({
    required String sku,
    String? selectedSize,
  }) {
    final sizeToken = normalizeSize(selectedSize);
    if (sizeToken == null) return '${sku}_no_size';
    return '${sku}_$sizeToken';
  }

  factory CartItem.fromProduct({
    required ProductItem product,
    String? selectedSize,
    int quantity = 1,
  }) {
    final sizeToken = normalizeSize(selectedSize);
    return CartItem(
      id: composeId(sku: product.sku, selectedSize: sizeToken),
      productId: product.id,
      selectedSize: sizeToken,
      quantity: quantity,
      product: product,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'productId': productId,
        'selectedSize': selectedSize,
        'quantity': quantity,
        'isUnavailable': isUnavailable,
        if (product != null) 'product': product!.toJson(),
      };

  factory CartItem.fromJson(Map<String, dynamic> json) {
    ProductItem? product;
    final rawProduct = json['product'];
    if (rawProduct is Map) {
      product = ProductItem.fromJson(Map<String, dynamic>.from(rawProduct));
    }

    final productId =
        json['productId'] as String? ?? product?.id ?? json['id']?.toString();

    return CartItem(
      id: json['id'] as String? ??
          composeId(
            sku: product?.sku ?? productId ?? '',
            selectedSize: json['selectedSize'] as String?,
          ),
      productId: productId ?? '',
      selectedSize: json['selectedSize'] as String?,
      quantity: json['quantity'] as int? ?? 1,
      product: product,
      isUnavailable: json['isUnavailable'] as bool? ?? false,
    );
  }

  /// Миграция с legacy-снимка (`product` + `cartKey` без id).
  factory CartItem.fromLegacyJson(Map<String, dynamic> json) {
    final product = ProductItem.fromJson(
      Map<String, dynamic>.from(json['product'] as Map),
    );
    final legacySize = (json['selectedSize'] as num?)?.toDouble();
    final sizeToken = legacySize?.toString();
    final legacyKey = json['cartKey'] as String?;
    final id = legacyKey ??
        composeId(sku: product.sku, selectedSize: sizeToken);
    return CartItem(
      id: id,
      productId: product.id,
      selectedSize: sizeToken,
      quantity: json['quantity'] as int? ?? 1,
      product: product,
    );
  }
}
