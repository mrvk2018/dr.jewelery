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
}

/// Демонстрационные заказы для профиля и админки.
const demoProfileOrders = <OrderItem>[
  OrderItem(
    id: 'ORD-1042',
    productName: 'Кольцо из белого золота с бриллиантом',
    amount: 14990,
    status: OrderStatus.delivered,
    dateLabel: '28 авг 2026',
    customerName: 'Анна Иванова',
  ),
  OrderItem(
    id: 'ORD-1087',
    productName: 'Серьги с изумрудом',
    amount: 22990,
    status: OrderStatus.paid,
    dateLabel: '3 сен 2026',
    customerName: 'Анна Иванова',
  ),
];

const demoAdminOrders = <OrderItem>[
  OrderItem(
    id: 'ORD-1101',
    productName: 'Подвеска «Сердце»',
    amount: 11990,
    status: OrderStatus.newOrder,
    dateLabel: '5 сен 2026',
    customerName: 'Мария Петрова',
  ),
  OrderItem(
    id: 'ORD-1098',
    productName: 'Браслет с фианитами',
    amount: 4990,
    status: OrderStatus.paid,
    dateLabel: '4 сен 2026',
    customerName: 'Елена Смирнова',
  ),
  OrderItem(
    id: 'ORD-1091',
    productName: 'Часы «Sunlight Classic»',
    amount: 45990,
    status: OrderStatus.delivered,
    dateLabel: '1 сен 2026',
    customerName: 'Олег Кузнецов',
  ),
  ...demoProfileOrders,
];
