class ScrapFinenessRow {
  ScrapFinenessRow({
    required this.fineness,
    this.grossWeight = 0,
    this.stoneDiscountPercent = 0,
    this.customFineness = false,
  });

  double fineness;
  double grossWeight;
  double stoneDiscountPercent;
  final bool customFineness;

  double get netWeight {
    if (grossWeight <= 0) return 0;
    final pct = stoneDiscountPercent.clamp(0, 100);
    return grossWeight * (1 - pct / 100);
  }

  double equivalentToStandard(double standardProbe) {
    if (netWeight <= 0 || fineness <= 0 || standardProbe <= 0) return 0;
    return netWeight * fineness / standardProbe;
  }

  Map<String, dynamic> toPayloadGold() {
    final eq = equivalentToStandard(585);
    return {
      'fineness': fineness,
      'gross_weight': grossWeight,
      'stone_discount_percent': stoneDiscountPercent,
      'net_weight': double.parse(netWeight.toStringAsFixed(4)),
      'equivalent_585_weight': double.parse(eq.toStringAsFixed(4)),
    };
  }

  Map<String, dynamic> toPayloadSilver() {
    final eq = equivalentToStandard(925);
    return {
      'fineness': fineness,
      'gross_weight': grossWeight,
      'stone_discount_percent': stoneDiscountPercent,
      'net_weight': double.parse(netWeight.toStringAsFixed(4)),
      'equivalent_925_weight': double.parse(eq.toStringAsFixed(4)),
    };
  }

  static List<ScrapFinenessRow> activeRows(Iterable<ScrapFinenessRow> rows) {
    return rows.where((r) => r.grossWeight > 0 && r.fineness > 0).toList();
  }
}

class ScrapPayoutBreakdown {
  const ScrapPayoutBreakdown({
    this.totalEquivalent = 0,
    this.tradeinPaidGrams = 0,
    this.standardPaidGrams = 0,
    this.payoutKrw = 0,
  });

  final double totalEquivalent;
  final double tradeinPaidGrams;
  final double standardPaidGrams;
  final int payoutKrw;
}

abstract final class ScrapMetalCalculator {
  static ScrapPayoutBreakdown computePayout({
    required double totalEquivalent,
    required double purchaseOffsetGrams,
    required int standardRateKrw,
    required int tradeinRateKrw,
  }) {
    final total = totalEquivalent < 0 ? 0.0 : totalEquivalent;
    final offset = purchaseOffsetGrams < 0 ? 0.0 : purchaseOffsetGrams;
    final tradein = offset < total ? offset : total;
    final standard = total - tradein;
    final payout = (tradein * tradeinRateKrw + standard * standardRateKrw).round();
    return ScrapPayoutBreakdown(
      totalEquivalent: total,
      tradeinPaidGrams: tradein,
      standardPaidGrams: standard,
      payoutKrw: payout < 0 ? 0 : payout,
    );
  }

  static double sumGoldEquivalent(Iterable<ScrapFinenessRow> rows) {
    return ScrapFinenessRow.activeRows(rows)
        .fold(0.0, (s, r) => s + r.equivalentToStandard(585));
  }

  static double sumSilverEquivalent(Iterable<ScrapFinenessRow> rows) {
    return ScrapFinenessRow.activeRows(rows)
        .fold(0.0, (s, r) => s + r.equivalentToStandard(925));
  }
}