/// Способ доставки заказа (логистика Южной Кореи).
enum DeliveryMethod {
  courier,
  pickup;

  int get feeKrw => switch (this) {
        DeliveryMethod.courier => 3000,
        DeliveryMethod.pickup => 0,
      };

  bool get isFree => feeKrw == 0;
}
