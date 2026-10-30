import 'package:intl/intl.dart';

/// Форматирует сумму в корейских вонах: `₩150,000`.
String formatWon(int price) {
  return NumberFormat.currency(
    locale: 'ko_KR',
    symbol: '₩',
    decimalDigits: 0,
  ).format(price);
}

/// Воны для термопринтера: ASCII-разделители, символ ₩ без locale-пробелов.
String formatWonForLabel(int price) {
  final safe = price.clamp(0, 999999999);
  final digits = NumberFormat('#,##0', 'en_US').format(safe);
  return '₩$digits';
}
