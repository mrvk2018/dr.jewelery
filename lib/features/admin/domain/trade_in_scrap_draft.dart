/// Черновик приёмки лома из POS Trade-In (до атомарного checkout).
class TradeInScrapDraft {
  const TradeInScrapDraft({
    required this.scrapPayload,
    required this.scrapTotalKrw,
    required this.cartTotalKrw,
    required this.cartGoldWeightGrams,
    required this.netCashDeltaKrw,
    required this.goldEquivalent585,
    required this.storeLocation,
  });

  /// Payload для `upsert_scrap_metal_intake` / checkout RPC (без `id`).
  final Map<String, dynamic> scrapPayload;

  /// Сумма лома после округления вниз до 1 000 ₩.
  final int scrapTotalKrw;

  final int cartTotalKrw;

  /// Снимок суммарного веса золота в корзине на момент привязки.
  final double cartGoldWeightGrams;

  /// cartTotal − scrapTotal (знак: + от клиента, − доплата клиенту).
  final int netCashDeltaKrw;

  final double goldEquivalent585;

  final String storeLocation;
}