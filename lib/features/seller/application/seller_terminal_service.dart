import 'package:flutter/foundation.dart';

import '../../../core/services/database_service.dart';
import '../data/seller_token_store.dart';
import '../domain/seller_pos_pricing.dart';

/// Фасад POS-терминала: токен, смены, каталог, RPC продажи и трансферов.
class SellerTerminalService {
  SellerTerminalService({
    required DatabaseService database,
    required SellerTokenStore tokenStore,
  })  : _database = database,
        _tokenStore = tokenStore;

  final DatabaseService _database;
  final SellerTokenStore _tokenStore;

  String? get sellerCode => _tokenStore.staffCode;

  Future<void> bindSellerCode(String code) => _tokenStore.saveStaffCode(code);

  Future<String?> startShift() async {
    final code = sellerCode;
    if (code == null) return null;
    return _database.startStaffShift(code);
  }

  Future<bool> endShift(String shiftId) => _database.endStaffShift(shiftId);

  Future<Map<String, dynamic>?> loadProductByQr(String qrPayload) {
    return _database.fetchProductByQrPayload(qrPayload);
  }

  Future<Map<String, dynamic>> confirmSale({
    required String qrPayload,
    required int basePriceKrw,
    required int discountPercent,
  }) {
    final code = sellerCode;
    if (code == null) {
      return Future.value({'ok': false, 'error': 'seller_not_bound'});
    }
    final quote = SellerPosPricing.quote(
      basePriceKrw: basePriceKrw,
      discountPercent: discountPercent,
    );
    return _database.processPosQrSale(
      qrPayload: qrPayload,
      sellerCode: code,
      discountPercent: discountPercent,
      deliveryFeeKrw: quote.deliveryFeeKrw,
      saleTotalKrw: quote.totalKrw,
    );
  }

  Future<Map<String, dynamic>> sendTransfer({
    required String qrPayload,
    required String toLocation,
  }) {
    final code = sellerCode;
    if (code == null) {
      return Future.value({'ok': false, 'error': 'seller_not_bound'});
    }
    return _database.initiateProductTransfer(
      qrPayload: qrPayload,
      sellerCode: code,
      toLocation: toLocation,
    );
  }

  Future<Map<String, dynamic>> receiveTransfer(String qrPayload) {
    final code = sellerCode;
    if (code == null) {
      return Future.value({'ok': false, 'error': 'seller_not_bound'});
    }
    return _database.completeProductTransfer(
      qrPayload: qrPayload,
      receiverCode: code,
    );
  }

  static int readBasePriceKrw(Map<String, dynamic> product) {
    final sale = (product['sale_price'] as num?)?.toInt();
    if (sale != null && sale > 0) return sale;
    final base = (product['base_price'] as num?)?.toInt();
    if (base != null && base > 0) return base;
    debugPrint('SellerTerminalService: base price missing for ${product['sku']}');
    return 0;
  }
}
