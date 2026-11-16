/// Ответ RPC [apply_seller_referral_promo].
class SellerReferralApplyResult {
  const SellerReferralApplyResult({
    required this.ok,
    this.alreadyReferred = false,
    this.discountPercent = 0,
    this.goldDiscountPercent = 0,
    this.silverDiscountPercent = 0,
    this.message,
    this.sellerCode,
    this.sellerName,
    this.errorCode,
  });

  final bool ok;
  final bool alreadyReferred;
  final int discountPercent;
  final int goldDiscountPercent;
  final int silverDiscountPercent;
  final String? message;
  final String? sellerCode;
  final String? sellerName;
  final String? errorCode;

  factory SellerReferralApplyResult.fromJson(Map<String, dynamic> json) {
    final gold = (json['gold_discount_percent'] as num?)?.toInt();
    final silver = (json['silver_discount_percent'] as num?)?.toInt();
    final legacy = (json['discount_percent'] as num?)?.toInt() ?? 0;
    return SellerReferralApplyResult(
      ok: json['ok'] as bool? ?? false,
      alreadyReferred: json['already_referred'] as bool? ?? false,
      discountPercent: legacy,
      goldDiscountPercent: gold ?? legacy,
      silverDiscountPercent: silver ?? legacy,
      message: json['message'] as String?,
      sellerCode: json['seller_code'] as String?,
      sellerName: json['seller_name'] as String?,
      errorCode: json['error'] as String?,
    );
  }
}