/// Запись картотеки продавцов / блогеров (промокод реферальной системы).
class SellerItem {
  SellerItem({
    required this.promoCode,
    required this.name,
    this.isActive = true,
    this.buyerBonusKrw = 0,
    this.buyerBonusPercent = 0,
    this.goldCommissionPercent = 0,
    this.silverCommissionPercent = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String promoCode;
  final String name;
  final bool isActive;
  final int buyerBonusKrw;
  final int buyerBonusPercent;
  final double goldCommissionPercent;
  final double silverCommissionPercent;
  final DateTime createdAt;

  SellerItem copyWith({
    String? promoCode,
    String? name,
    bool? isActive,
    int? buyerBonusKrw,
    int? buyerBonusPercent,
    double? goldCommissionPercent,
    double? silverCommissionPercent,
    DateTime? createdAt,
  }) {
    return SellerItem(
      promoCode: promoCode ?? this.promoCode,
      name: name ?? this.name,
      isActive: isActive ?? this.isActive,
      buyerBonusKrw: buyerBonusKrw ?? this.buyerBonusKrw,
      buyerBonusPercent: buyerBonusPercent ?? this.buyerBonusPercent,
      goldCommissionPercent:
          goldCommissionPercent ?? this.goldCommissionPercent,
      silverCommissionPercent:
          silverCommissionPercent ?? this.silverCommissionPercent,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'promoCode': promoCode,
        'name': name,
        'isActive': isActive,
        'buyerBonusKrw': buyerBonusKrw,
        'buyerBonusPercent': buyerBonusPercent,
        'goldCommissionPercent': goldCommissionPercent,
        'silverCommissionPercent': silverCommissionPercent,
        'createdAt': createdAt.toIso8601String(),
      };

  factory SellerItem.fromJson(Map<String, dynamic> json) {
    return SellerItem(
      promoCode: json['promoCode'] as String,
      name: json['name'] as String,
      isActive: json['isActive'] as bool? ?? true,
      buyerBonusKrw: (json['buyerBonusKrw'] as num?)?.toInt() ?? 0,
      buyerBonusPercent: (json['buyerBonusPercent'] as num?)?.toInt() ?? 0,
      goldCommissionPercent:
          (json['goldCommissionPercent'] as num?)?.toDouble() ?? 0,
      silverCommissionPercent:
          (json['silverCommissionPercent'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  static double? parseCommissionPercentInput(String raw) {
    final normalized = raw.trim().replaceAll(',', '.');
    if (normalized.isEmpty) return 0;
    return double.tryParse(normalized);
  }

  static String normalizePromoCode(String raw) =>
      raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
}
