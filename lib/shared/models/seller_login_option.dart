/// Строка для выпадающего списка входа продавца (без пароля/PIN).
class SellerLoginOption {
  const SellerLoginOption({
    required this.promoCode,
    required this.name,
    required this.hasPin,
  });

  final String promoCode;
  final String name;
  final bool hasPin;

  factory SellerLoginOption.fromJson(Map<String, dynamic> json) {
    return SellerLoginOption(
      promoCode: (json['promo_code'] ?? json['promoCode'] ?? '')
          .toString()
          .trim()
          .toUpperCase(),
      name: (json['name'] ?? '').toString().trim(),
      hasPin: json['has_pin'] == true || json['hasPin'] == true,
    );
  }
}