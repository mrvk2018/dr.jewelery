import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/models/seller_item.dart';
import '../../shared/providers/cart_controller.dart';

/// Telegram-группа розничной сети (5 магазинов).
abstract final class RetailTelegramConfig {
  /// Legacy slug Edge Function; доставка — через Telegram Bot API на сервере.
  static const edgeFunctionName = 'send_whatsapp_notification';

  /// Поле legacy payload (чат задаётся `TELEGRAM_CHAT_ID` на сервере).
  static const legacyRecipientField = '+821023377069';
}

/// Карточка продажи в Telegram через Supabase Edge Function.
class RetailNotificationService {
  RetailNotificationService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  /// POST к Edge Function [RetailTelegramConfig.edgeFunctionName] → Telegram.
  ///
  /// Возвращает `true`, если HTTP-вызов завершился без ошибки (2xx).
  Future<bool> sendTelegramOrderNotification({
    required String orderId,
    required List<CartItem> cartItems,
    int? totalAmountKrw,
    String? sellerCode,
    String? sellerName,
  }) async {
    if (orderId.trim().isEmpty || cartItems.isEmpty) {
      debugPrint('sendTelegramOrderNotification: пустой orderId или корзина');
      return false;
    }

    final code = sellerCode?.trim() ?? '';
    var name = sellerName?.trim() ?? '';
    if (code.isNotEmpty && name.isEmpty) {
      name = await _lookupSellerNameByPromoCode(code) ?? '';
    }

    final payload = <String, dynamic>{
      'recipient': RetailTelegramConfig.legacyRecipientField,
      'order_id': orderId,
      'total_amount_krw': ?totalAmountKrw,
      'items': cartItems.map(_cartLinePayload).toList(),
      if (code.isNotEmpty) 'seller_code': code,
      if (name.isNotEmpty) 'seller_name': name,
    };

    try {
      final response = await _client.functions.invoke(
        RetailTelegramConfig.edgeFunctionName,
        body: payload,
      );

      final status = response.status;
      if (status >= 200 && status < 300) {
        return true;
      }

      debugPrint(
        'sendTelegramOrderNotification: HTTP $status — ${response.data}',
      );
      return false;
    } catch (error, stackTrace) {
      debugPrint('sendTelegramOrderNotification failed: $error');
      debugPrint('$stackTrace');
    }
    return false;
  }

  Future<String?> _lookupSellerNameByPromoCode(String promoCode) async {
    try {
      final row = await _client
          .from('sellers')
          .select('name')
          .eq('promo_code', SellerItem.normalizePromoCode(promoCode))
          .maybeSingle();
      if (row == null) return null;
      final name = (row['name'] as String?)?.trim();
      return name == null || name.isEmpty ? null : name;
    } catch (error, stackTrace) {
      debugPrint('_lookupSellerNameByPromoCode failed: $error');
      debugPrint('$stackTrace');
      return null;
    }
  }

  /// Поля карточки для розницы (SKU, вес, размер, камни, фото).
  static Map<String, dynamic> _cartLinePayload(CartItem line) {
    final product = line.product;
    return {
      'sku': product.sku,
      'warehouse_item_id': product.id,
      'weight': _formatWeight(product.weightGrams),
      'size': _resolveSize(line),
      'price_krw': product.salePrice * line.quantity,
      'unit_price_krw': product.salePrice,
      'quantity': line.quantity,
      'stones': product.insert,
      'image_url': product.imageUrl,
    };
  }

  static String _formatWeight(double? grams) {
    if (grams == null) return '';
    final rounded = grams == grams.roundToDouble()
        ? grams.toInt().toString()
        : grams.toString();
    return '$rounded g';
  }

  static String _resolveSize(CartItem line) {
    if (line.selectedSize != null) {
      return line.selectedSize.toString();
    }
    if (line.product.availableSizes.isEmpty) return '';
    return line.product.availableSizes.join(', ');
  }
}

/// Единая точка доступа с экрана оплаты.
final retailNotificationService = RetailNotificationService();
