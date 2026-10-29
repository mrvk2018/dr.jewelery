import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Серверное подтверждение платежа Toss (secret key только на Edge Function).
class TossPaymentConfirmationService {
  TossPaymentConfirmationService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  static const edgeFunctionName = 'confirm-toss-payment';

  final SupabaseClient _client;

  /// POST на Supabase Edge Function: проверка `paymentKey` + суммы на сервере.
  ///
  /// Сейчас — каркас: логирует вызов; при деплое функции вернёт JSON ответа.
  Future<Map<String, dynamic>> confirmPaymentViaEdgeFunction({
    required String paymentKey,
    required String orderId,
    required int amount,
  }) async {
    if (paymentKey.trim().isEmpty) {
      throw ArgumentError.value(paymentKey, 'paymentKey', 'must not be empty');
    }
    if (orderId.trim().isEmpty) {
      throw ArgumentError.value(orderId, 'orderId', 'must not be empty');
    }
    if (amount <= 0) {
      throw ArgumentError.value(amount, 'amount', 'must be positive');
    }

    try {
      final response = await _client.functions.invoke(
        edgeFunctionName,
        body: {
          'paymentKey': paymentKey.trim(),
          'orderId': orderId.trim(),
          'amount': amount,
        },
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        return data;
      }
      if (data is Map) {
        return Map<String, dynamic>.from(data);
      }

      return {
        'success': response.status >= 200 && response.status < 300,
        'status': response.status,
        'data': data,
      };
    } catch (error, stackTrace) {
      debugPrint(
        'TossPaymentConfirmationService.confirmPaymentViaEdgeFunction '
        'not ready: $error',
      );
      debugPrint('$stackTrace');
      rethrow;
    }
  }

  bool isSuccessful(Map<String, dynamic> response) =>
      response['success'] == true;
}
