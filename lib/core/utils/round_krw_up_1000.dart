/// Округление цены изделия вверх до 1 000 ₩ (в пользу магазина).
int roundKrwUpTo1000(num amount) {
  if (amount <= 0) return 0;
  return (((amount - 1e-6) / 1000).ceil() * 1000).toInt();
}