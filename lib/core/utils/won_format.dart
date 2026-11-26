import 'package:intl/intl.dart';

/// Два неразрывных пробела между ₩ и цифрами.
const String kKrwWonNumberGap = '\u00A0\u00A0';

/// Цифры с разделителем тысяч (знака нет).
String formatKrwDigits(num amount) {
  final safe = amount.abs().round();
  return NumberFormat('#,##0', 'en_US').format(safe);
}

/// Строка: `₩··2,217,000`, `−₩··189,000`, `+₩··141,000`.
String formatWon(
  int price, {
  bool showPlusSign = false,
}) {
  final sign = price < 0 ? '−' : (showPlusSign && price > 0 ? '+' : '');
  return '$sign₩$kKrwWonNumberGap${formatKrwDigits(price)}';
}

/// Дельта: плюс только при положительном значении.
String formatWonDelta(int price) {
  if (price > 0) return formatWon(price, showPlusSign: true);
  if (price < 0) return formatWon(price);
  return formatWon(0);
}

/// Компактно для PDF/термобирки 60×12 мм (без двойного отступа).
String formatWonForLabel(int price) {
  final safe = price.abs().clamp(0, 999999999);
  final digits = NumberFormat('#,##0', 'en_US').format(safe);
  final sign = price < 0 ? '−' : '';
  return '$sign₩$digits';
}