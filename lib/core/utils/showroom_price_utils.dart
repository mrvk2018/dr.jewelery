/// Витринная цена до POS-скидки: [sale_price] | [price], без marketing `old_price`.
int productShowroomListPriceKrw(Map<String, dynamic> map) {
  final sale = (map['sale_price'] as num?)?.toInt() ?? 0;
  if (sale > 0) return sale;
  final price = (map['price'] as num?)?.toInt() ?? 0;
  if (price > 0) return price;
  return 0;
}

/// Формат бирки: `195 000 ₩` (пробелы тысяч, кириллица и ₩).
String formatShowroomWonForJewelryLabel(int krw) {
  final safe = krw.clamp(0, 999999999);
  final spaced = safe.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (m) => '${m[1]} ',
  );
  return '$spaced ₩';
}