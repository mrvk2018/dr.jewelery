/// Строка журнала `list_product_transfers` (+ обогащение 046: image_url, product_name).
class ProductTransferItem {
  const ProductTransferItem({
    required this.raw,
    this.id,
    this.productId,
    this.sku,
    this.status,
    this.fromStore,
    this.toStore,
    this.senderCode,
    this.metalType,
    this.weightGrams,
    this.notes,
    this.createdAt,
    this.imageUrl,
    this.productName,
  });

  final Map<String, dynamic> raw;
  final String? id;
  final String? productId;
  final String? sku;
  final String? status;
  final String? fromStore;
  final String? toStore;
  final String? senderCode;
  final String? metalType;
  final double? weightGrams;
  final String? notes;
  final String? createdAt;
  final String? imageUrl;
  final String? productName;

  factory ProductTransferItem.fromMap(Map<String, dynamic> map) {
    final weight = map['weight_grams'];
    final parsedWeight =
        weight is num ? weight.toDouble() : double.tryParse('$weight');

    return ProductTransferItem(
      raw: map,
      id: map['id']?.toString(),
      productId: map['product_id']?.toString(),
      sku: map['sku']?.toString(),
      status: map['status']?.toString(),
      fromStore: map['from_store']?.toString(),
      toStore: map['to_store']?.toString(),
      senderCode: map['sender_code']?.toString(),
      metalType: map['metal_type']?.toString(),
      weightGrams: parsedWeight,
      notes: map['notes']?.toString(),
      createdAt: map['created_at']?.toString(),
      imageUrl: map['image_url']?.toString().trim(),
      productName: map['product_name']?.toString().trim(),
    );
  }
}