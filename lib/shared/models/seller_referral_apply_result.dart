/// Ответ RPC [apply_seller_referral_promo].
class SellerReferralApplyResult {
  const SellerReferralApplyResult({
    required this.ok,
    this.alreadyReferred = false,
    this.discountPercent = 0,
    this.message,
    this.sellerCode,
    this.errorCode,
  });

  final bool ok;
  final bool alreadyReferred;
  final int discountPercent;
  final String? message;
  final String? sellerCode;
  final String? errorCode;

  factory SellerReferralApplyResult.fromJson(Map<String, dynamic> json) {
    return SellerReferralApplyResult(
      ok: json['ok'] as bool? ?? false,
      alreadyReferred: json['already_referred'] as bool? ?? false,
      discountPercent: (json['discount_percent'] as num?)?.toInt() ?? 0,
      message: json['message'] as String?,
      sellerCode: json['seller_code'] as String?,
      errorCode: json['error'] as String?,
    );
  }
}
