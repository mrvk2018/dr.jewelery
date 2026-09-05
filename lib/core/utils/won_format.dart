import 'package:intl/intl.dart';

/// Форматирует сумму в корейских вонах: `₩150,000`.
String formatWon(int price) {
  return NumberFormat.currency(
    locale: 'ko_KR',
    symbol: '₩',
    decimalDigits: 0,
  ).format(price);
}
