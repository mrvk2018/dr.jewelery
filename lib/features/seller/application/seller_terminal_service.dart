import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/database_service.dart';
import '../data/seller_token_store.dart';
import '../domain/seller_pos_pricing.dart';

/// Фасад POS-терминала: токен, kill-switch, смены, RPC продажи и трансферов.
class SellerTerminalService {
  SellerTerminalService({
    required DatabaseService database,
    required SellerTokenStore tokenStore,
  })  : _database = database,
        _tokenStore = tokenStore;

  final DatabaseService _database;
  final SellerTokenStore _tokenStore;

  bool _accessRevokedPending = false;

  DatabaseService get database => _database;

  String? get sellerCode => _tokenStore.staffCode;

  bool consumeAccessRevoked() {
    final pending = _accessRevokedPending;
    _accessRevokedPending = false;
    return pending;
  }

  Future<bool> validateStaffCode(String code) {
    return _database.isSellerStaffActive(code.trim().toUpperCase());
  }

  Future<bool> bindSellerCode(String code) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) return false;
    final active = await _database.isSellerStaffActive(normalized);
    if (!active) {
      await executeKillSwitch();
      return false;
    }
    await _tokenStore.saveStaffCode(normalized);
    return true;
  }

  Future<void> executeKillSwitch() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await _tokenStore.clear();
    _accessRevokedPending = true;
  }

  Future<bool> _guardActive() async {
    final code = sellerCode;
    if (code == null) return false;
    final active = await _database.isSellerStaffActive(code);
    if (!active) {
      await executeKillSwitch();
      return false;
    }
    return true;
  }

  Future<String?> startShift() async {
    if (!await _guardActive()) return null;
    final code = sellerCode;
    if (code == null) return null;
    return _database.startStaffShift(code);
  }

  Future<bool> endShift(String shiftId) async {
    if (!await _guardActive()) return false;
    return _database.endStaffShift(shiftId);
  }

  Future<Map<String, dynamic>?> loadProductByQr(String qrPayload) async {
    if (!await _guardActive()) return null;
    return _database.fetchProductByQrPayload(qrPayload);
  }

  Future<List<Map<String, dynamic>>> loadInboundTransfers(String toStore) async {
    if (!await _guardActive()) return const [];
    return _database.fetchInboundProductTransfers(toStore);
  }

  Future<Map<String, dynamic>> confirmSale({
    required String qrPayload,
    required int basePriceKrw,
    required int discountPercent,
  }) async {
    if (!await _guardActive()) {
      return {'ok': false, 'error': 'access_revoked'};
    }
    final code = sellerCode;
    if (code == null) {
      return {'ok': false, 'error': 'seller_not_bound'};
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
  }) async {
    if (!await _guardActive()) {
      return {'ok': false, 'error': 'access_revoked'};
    }
    final code = sellerCode;
    if (code == null) {
      return {'ok': false, 'error': 'seller_not_bound'};
    }
    return _database.initiateProductTransfer(
      qrPayload: qrPayload,
      sellerCode: code,
      toLocation: toLocation,
    );
  }

  Future<Map<String, dynamic>> receiveTransfer(String qrPayload) async {
    if (!await _guardActive()) {
      return {'ok': false, 'error': 'access_revoked'};
    }
    final code = sellerCode;
    if (code == null) {
      return {'ok': false, 'error': 'seller_not_bound'};
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
