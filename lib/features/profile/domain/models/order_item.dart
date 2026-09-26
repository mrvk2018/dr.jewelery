/// Статус заказа в системе.
enum OrderStatus {
  newOrder('Новый'),
  paid('Оплачен'),
  delivered('Доставлен');

  const OrderStatus(this.label);

  final String label;
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
  });

  final String id;
  final String productName;
  final int amount;
  final OrderStatus status;
  final String dateLabel;
  final String customerName;

  Map<String, dynamic> toJson() => {
        'id': id,
        'productName': productName,
        'amount': amount,
        'status': status.name,
        'dateLabel': dateLabel,
        'customerName': customerName,
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
    );
  }

  factory OrderItem.fromSupabase(Map<String, dynamic> json) {
    final createdAt = json['created_at'] != null
        ? DateTime.parse(json['created_at'].toString())
        : DateTime.now();
    final dateStr = '${createdAt.day}.${createdAt.month}.${createdAt.year}';
    final statusRaw = json['status'] as String? ?? '';
    final status = statusRaw == 'delivered'
        ? OrderStatus.delivered
        : statusRaw == 'paid'
            ? OrderStatus.paid
            : OrderStatus.newOrder;
    return OrderItem(
      id: json['id'].toString(),
      productName: json['product_name'] as String? ?? 'Ювелирное изделие',
      amount: (json['amount'] as num? ?? 0).toInt(),
      status: status,
      dateLabel: dateStr,
      customerName: json['customer_name'] as String? ?? 'Покупатель',
    );
  }

  static String statusToSupabase(OrderStatus status) {
    return switch (status) {
      OrderStatus.delivered => 'delivered',
      OrderStatus.paid => 'paid',
      OrderStatus.newOrder => 'new',
    };
  }
}
