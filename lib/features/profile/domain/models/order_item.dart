/// Статус заказа в системе.
enum OrderStatus {
  newOrder('Новый'),
  paid('Оплачен'),
  inTransit('В пути'),
  delivered('Доставлен');

  const OrderStatus(this.label);

  final String label;

  static OrderStatus fromSupabaseStatus(String? raw) {
    return switch (raw) {
      'delivered' => OrderStatus.delivered,
      'in_transit' => OrderStatus.inTransit,
      'paid' => OrderStatus.paid,
      _ => OrderStatus.newOrder,
    };
  }
}

/// Модель заказа для истории и админ-панели.
class OrderItem {
  const OrderItem({
    required this.id,
    required this.productName,
    required this.amount,
    required this.status,
    required this.dateLabel,
    required this.customerName,
    this.shippingPostalCode = '',
    this.shippingRoadAddress = '',
    this.shippingDetailAddress = '',
    this.recipientName = '',
    this.recipientPhone = '',
    this.sellerCode = '',
  });

  final String id;
  final String productName;
  final int amount;
  final OrderStatus status;
  final String dateLabel;
  final String customerName;
  final String shippingPostalCode;
  final String shippingRoadAddress;
  final String shippingDetailAddress;
  final String recipientName;
  final String recipientPhone;
  final String sellerCode;

  bool get hasShippingAddress =>
      shippingPostalCode.isNotEmpty ||
      shippingRoadAddress.isNotEmpty ||
      shippingDetailAddress.isNotEmpty;

  /// Формат для буфера обмена (админ «Скопировать адрес»).
  String get formattedShippingAddressKr {
    final lines = <String>[
      if (recipientName.isNotEmpty) recipientName,
      if (recipientPhone.isNotEmpty) recipientPhone,
      if (shippingPostalCode.isNotEmpty) '($shippingPostalCode)',
      if (shippingRoadAddress.isNotEmpty) shippingRoadAddress,
      if (shippingDetailAddress.isNotEmpty) shippingDetailAddress,
    ];
    return lines.join('\n');
  }

  OrderItem copyWith({
    OrderStatus? status,
  }) {
    return OrderItem(
      id: id,
      productName: productName,
      amount: amount,
      status: status ?? this.status,
      dateLabel: dateLabel,
      customerName: customerName,
      shippingPostalCode: shippingPostalCode,
      shippingRoadAddress: shippingRoadAddress,
      shippingDetailAddress: shippingDetailAddress,
      recipientName: recipientName,
      recipientPhone: recipientPhone,
      sellerCode: sellerCode,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'productName': productName,
        'amount': amount,
        'status': status.name,
        'dateLabel': dateLabel,
        'customerName': customerName,
        'shippingPostalCode': shippingPostalCode,
        'shippingRoadAddress': shippingRoadAddress,
        'shippingDetailAddress': shippingDetailAddress,
        'recipientName': recipientName,
        'recipientPhone': recipientPhone,
        'sellerCode': sellerCode,
      };

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    final statusName = json['status'] as String? ?? OrderStatus.paid.name;
    return OrderItem(
      id: json['id'] as String,
      productName: json['productName'] as String,
      amount: json['amount'] as int,
      status: OrderStatus.values.firstWhere(
        (status) => status.name == statusName,
        orElse: () => OrderStatus.paid,
      ),
      dateLabel: json['dateLabel'] as String? ?? '',
      customerName: json['customerName'] as String? ?? '',
      shippingPostalCode: json['shippingPostalCode'] as String? ?? '',
      shippingRoadAddress: json['shippingRoadAddress'] as String? ?? '',
      shippingDetailAddress: json['shippingDetailAddress'] as String? ?? '',
      recipientName: json['recipientName'] as String? ?? '',
      recipientPhone: json['recipientPhone'] as String? ?? '',
      sellerCode: json['sellerCode'] as String? ?? '',
    );
  }

  factory OrderItem.fromSupabase(Map<String, dynamic> json) {
    final createdAt = json['created_at'] != null
        ? DateTime.parse(json['created_at'].toString())
        : DateTime.now();
    final dateStr = '${createdAt.day}.${createdAt.month}.${createdAt.year}';
    final statusRaw = json['status'] as String? ?? '';
    return OrderItem(
      id: json['id'].toString(),
      productName: json['product_name'] as String? ?? 'Ювелирное изделие',
      amount: (json['amount'] as num? ?? 0).toInt(),
      status: OrderStatus.fromSupabaseStatus(statusRaw),
      dateLabel: dateStr,
      customerName: json['customer_name'] as String? ?? 'Покупатель',
      shippingPostalCode: json['shipping_postal_code'] as String? ?? '',
      shippingRoadAddress: json['shipping_road_address'] as String? ?? '',
      shippingDetailAddress: json['shipping_detail_address'] as String? ?? '',
      recipientName: json['recipient_name'] as String? ?? '',
      recipientPhone: json['recipient_phone'] as String? ?? '',
      sellerCode: json['seller_code'] as String? ?? '',
    );
  }

  static String statusToSupabase(OrderStatus status) {
    return switch (status) {
      OrderStatus.delivered => 'delivered',
      OrderStatus.inTransit => 'in_transit',
      OrderStatus.paid => 'paid',
      OrderStatus.newOrder => 'new',
    };
  }

  /// Значения для админ-dropdown (после оплаты).
  static const adminFulfillmentStatuses = ['paid', 'in_transit', 'delivered'];

  String get adminStatusDropdownValue {
    final raw = statusToSupabase(status);
    if (adminFulfillmentStatuses.contains(raw)) return raw;
    return 'paid';
  }
}
