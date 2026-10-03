/// Запись картотеки продавцов / блогеров (промокод реферальной системы).
class SellerItem {
  SellerItem({
    required this.promoCode,
    required this.name,
    this.isActive = true,
    this.buyerBonusKrw = 0,
    this.buyerBonusPercent = 0,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String promoCode;
  final String name;
  final bool isActive;
  final int buyerBonusKrw;
  final int buyerBonusPercent;
  final DateTime createdAt;

  SellerItem copyWith({
    String? promoCode,
    String? name,
    bool? isActive,
    int? buyerBonusKrw,
    int? buyerBonusPercent,
    DateTime? createdAt,
  }) {
    return SellerItem(
      promoCode: promoCode ?? this.promoCode,
      name: name ?? this.name,
      isActive: isActive ?? this.isActive,
      buyerBonusKrw: buyerBonusKrw ?? this.buyerBonusKrw,
      buyerBonusPercent: buyerBonusPercent ?? this.buyerBonusPercent,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'promoCode': promoCode,
        'name': name,
        'isActive': isActive,
        'buyerBonusKrw': buyerBonusKrw,
        'buyerBonusPercent': buyerBonusPercent,
        'createdAt': createdAt.toIso8601String(),
      };

  factory SellerItem.fromJson(Map<String, dynamic> json) {
    return SellerItem(
      promoCode: json['promoCode'] as String,
      name: json['name'] as String,
      isActive: json['isActive'] as bool? ?? true,
      buyerBonusKrw: (json['buyerBonusKrw'] as num?)?.toInt() ?? 0,
      buyerBonusPercent: (json['buyerBonusPercent'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  static String normalizePromoCode(String raw) =>
      raw.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
}
