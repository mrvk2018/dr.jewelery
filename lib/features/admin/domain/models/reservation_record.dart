class ReservationItemRecord {
  const ReservationItemRecord({
    required this.productId,
    required this.sku,
    required this.agreedPriceKrw,
    this.title,
    this.category,
    this.weightG,
    this.purity,
    this.size,
    this.listPriceKrw = 0,
  });

  final String productId;
  final String sku;
  final String? title;
  final String? category;
  final double? weightG;
  final String? purity;
  final String? size;
  final int listPriceKrw;
  final int agreedPriceKrw;

  String get specs {
    final parts = <String>[
      if (purity != null && purity!.trim().isNotEmpty) purity!.trim(),
      if (weightG != null && weightG! > 0) '${weightG!.toStringAsFixed(2)} г',
      if (size != null && size!.trim().isNotEmpty) 'размер ${size!.trim()}',
      if (category != null && category!.trim().isNotEmpty) category!.trim(),
    ];
    return parts.join(' · ');
  }
}

class ReservationPaymentRecord {
  const ReservationPaymentRecord({
    required this.paymentType,
    required this.amountKrw,
    required this.paymentMethod,
    required this.branch,
    this.createdAt,
    this.sellerName,
    this.receiptNumber,
  });

  final String paymentType;
  final int amountKrw;
  final String paymentMethod;
  final String branch;
  final DateTime? createdAt;
  final String? sellerName;
  final String? receiptNumber;
}

class ReservationRecord {
  const ReservationRecord({
    required this.id,
    required this.branch,
    required this.customerName,
    required this.customerPhone,
    required this.expiresAt,
    required this.totalAmountKrw,
    required this.paidDepositKrw,
    required this.balanceKrw,
    required this.status,
    required this.displayStatus,
    required this.isExpired,
    required this.items,
    required this.payments,
    this.receiptNumber,
    this.sellerName,
    this.sellerCode,
    this.comment,
    this.saleId,
    this.createdAt,
  });

  final String id;
  final String? receiptNumber;
  final String branch;
  final String? sellerName;
  final String? sellerCode;
  final String customerName;
  final String customerPhone;
  final DateTime? expiresAt;
  final String? comment;
  final int totalAmountKrw;
  final int paidDepositKrw;
  final int balanceKrw;
  final String status;
  final String displayStatus;
  final bool isExpired;
  final String? saleId;
  final DateTime? createdAt;
  final List<ReservationItemRecord> items;
  final List<ReservationPaymentRecord> payments;

  bool get canAct => status == 'active';

  static List<ReservationRecord> listFromRpc(Map<String, dynamic> raw) {
    final rows = raw['rows'];
    if (rows is! List) return const [];
    return rows
        .whereType<Map>()
        .map((row) => ReservationRecord.fromMap(Map<String, dynamic>.from(row)))
        .toList(growable: false);
  }

  factory ReservationRecord.fromMap(Map<String, dynamic> map) {
    return ReservationRecord(
      id: map['id']?.toString() ?? '',
      receiptNumber: _text(map['receipt_number']),
      branch: map['branch']?.toString() ?? '',
      sellerName: _text(map['seller_name']),
      sellerCode: _text(map['seller_code']),
      customerName: map['customer_name']?.toString() ?? '',
      customerPhone: map['customer_phone']?.toString() ?? '',
      expiresAt: _time(map['expires_at']),
      comment: _text(map['comment']),
      totalAmountKrw: _krw(map['total_amount_krw']),
      paidDepositKrw: _krw(map['paid_deposit_krw']),
      balanceKrw: _krw(map['balance_krw']),
      status: map['status']?.toString() ?? '',
      displayStatus: map['display_status']?.toString() ?? '',
      isExpired: map['is_expired'] == true,
      saleId: _text(map['sale_id']),
      createdAt: _time(map['created_at']),
      items: _items(map['items']),
      payments: _payments(map['payments']),
    );
  }

  static List<ReservationItemRecord> _items(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((row) {
      final map = Map<String, dynamic>.from(row);
      return ReservationItemRecord(
        productId: map['product_id']?.toString() ?? '',
        sku: map['sku']?.toString() ?? '',
        title: _text(map['title']),
        category: _text(map['category']),
        weightG: _double(map['weight_g']),
        purity: _text(map['purity']),
        size: _text(map['size']),
        listPriceKrw: _krw(map['list_price_krw']),
        agreedPriceKrw: _krw(map['agreed_price_krw']),
      );
    }).toList(growable: false);
  }

  static List<ReservationPaymentRecord> _payments(Object? raw) {
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((row) {
      final map = Map<String, dynamic>.from(row);
      return ReservationPaymentRecord(
        paymentType: map['payment_type']?.toString() ?? '',
        amountKrw: _krw(map['amount_krw']),
        paymentMethod: map['payment_method']?.toString() ?? '',
        branch: map['branch']?.toString() ?? '',
        createdAt: _time(map['created_at']),
        sellerName: _text(map['seller_name']),
        receiptNumber: _text(map['receipt_number']),
      );
    }).toList(growable: false);
  }

  static String? _text(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static int _krw(Object? value) {
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double? _double(Object? value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static DateTime? _time(Object? value) {
    final text = value?.toString();
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text)?.toLocal();
  }
}
