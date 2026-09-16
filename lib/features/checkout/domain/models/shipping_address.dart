/// Адрес доставки и контакт получателя с экрана checkout.
class ShippingAddress {
  const ShippingAddress({
    required this.postalCode,
    required this.roadAddress,
    required this.detailAddress,
    required this.recipientName,
    required this.phone,
    required this.deliveryMethod,
  });

  final String postalCode;
  final String roadAddress;
  final String detailAddress;
  final String recipientName;
  final String phone;
  final String deliveryMethod;

  Map<String, dynamic> toJson() => {
        'postalCode': postalCode,
        'roadAddress': roadAddress,
        'detailAddress': detailAddress,
        'recipientName': recipientName,
        'phone': phone,
        'deliveryMethod': deliveryMethod,
      };
}
