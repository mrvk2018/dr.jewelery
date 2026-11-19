class SellerPayrollRow {
  const SellerPayrollRow({
    required this.promoCode,
    required this.sellerName,
    required this.isActive,
    required this.goldCommissionPercent,
    required this.silverCommissionPercent,
    required this.goldSalesCount,
    required this.goldSalesKrw,
    required this.goldCommissionKrw,
    required this.silverSalesCount,
    required this.silverSalesKrw,
    required this.silverCommissionKrw,
    required this.returnsCount,
    required this.returnsCommissionKrw,
    required this.totalCommissionKrw,
  });

  static const unassignedCode = '__UNASSIGNED__';

  final String promoCode;
  final String sellerName;
  final bool isActive;
  final double goldCommissionPercent;
  final double silverCommissionPercent;
  final int goldSalesCount;
  final int goldSalesKrw;
  final int goldCommissionKrw;
  final int silverSalesCount;
  final int silverSalesKrw;
  final int silverCommissionKrw;
  final int returnsCount;
  final int returnsCommissionKrw;
  final int totalCommissionKrw;

  bool get isUnassigned => promoCode == unassignedCode;

  int get totalSalesKrw => goldSalesKrw + silverSalesKrw;

  factory SellerPayrollRow.fromMap(Map<String, dynamic> map) {
    double readNum(Object? raw) {
      if (raw is num) return raw.toDouble();
      return double.tryParse(raw?.toString() ?? '') ?? 0;
    }

    int readInt(Object? raw) {
      if (raw is num) return raw.toInt();
      return int.tryParse(raw?.toString() ?? '') ?? 0;
    }

    return SellerPayrollRow(
      promoCode: map['promo_code']?.toString() ?? '',
      sellerName: map['seller_name']?.toString() ?? '',
      isActive: map['is_active'] as bool? ?? true,
      goldCommissionPercent: readNum(map['gold_commission_percent']),
      silverCommissionPercent: readNum(map['silver_commission_percent']),
      goldSalesCount: readInt(map['gold_sales_count']),
      goldSalesKrw: readInt(map['gold_sales_krw']),
      goldCommissionKrw: readInt(map['gold_commission_krw']),
      silverSalesCount: readInt(map['silver_sales_count']),
      silverSalesKrw: readInt(map['silver_sales_krw']),
      silverCommissionKrw: readInt(map['silver_commission_krw']),
      returnsCount: readInt(map['returns_count']),
      returnsCommissionKrw: readInt(map['returns_commission_krw']),
      totalCommissionKrw: readInt(map['total_commission_krw']),
    );
  }
}

class SellerSaleDetailRow {
  const SellerSaleDetailRow({
    required this.saleId,
    this.soldAt,
    required this.sku,
    required this.productName,
    required this.metalCategory,
    required this.metalLabel,
    this.weightGrams,
    required this.priceKrw,
    required this.commissionPercent,
    required this.commissionKrw,
    required this.isReturn,
    this.imageUrl,
    this.soldDateKst,
  });

  final String saleId;
  final DateTime? soldAt;
  final String? soldDateKst;
  final String sku;
  final String productName;
  final String metalCategory;
  final String metalLabel;
  final double? weightGrams;
  final int priceKrw;
  final double commissionPercent;
  final int commissionKrw;
  final bool isReturn;
  final String? imageUrl;

  factory SellerSaleDetailRow.fromMap(Map<String, dynamic> map) {
    double? weight;
    final weightRaw = map['weight_grams'];
    if (weightRaw is num) {
      weight = weightRaw.toDouble();
    } else if (weightRaw != null) {
      weight = double.tryParse(weightRaw.toString());
    }

    DateTime? soldAt;
    final soldRaw = map['sold_at'];
    if (soldRaw is String && soldRaw.isNotEmpty) {
      soldAt = DateTime.tryParse(soldRaw);
    }

    return SellerSaleDetailRow(
      saleId: map['sale_id']?.toString() ?? '',
      soldAt: soldAt,
      sku: map['sku']?.toString() ?? '',
      productName: map['product_name']?.toString() ?? '',
      metalCategory: map['metal_category']?.toString() ?? 'other',
      metalLabel: map['metal_label']?.toString() ?? '',
      weightGrams: weight,
      priceKrw: (map['price_krw'] as num?)?.toInt() ?? 0,
      commissionPercent: (map['commission_percent'] as num?)?.toDouble() ?? 0,
      commissionKrw: (map['commission_krw'] as num?)?.toInt() ?? 0,
      isReturn: map['is_return'] == true,
      imageUrl: map['image_url']?.toString().trim(),
      soldDateKst: map['sold_date_kst']?.toString().trim(),
    );
  }
}