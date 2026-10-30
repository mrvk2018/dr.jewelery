import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android/iOS/desktop IO: передача TSPL/ZPL в нативный слой через MethodChannel.
abstract final class LabelPrinterBridge {
  static const _channel = MethodChannel('com.drjewelry.pos/printer');

  static Future<void> sendRawPayload(String payload) async {
    try {
      await _channel.invokeMethod<void>('printRawData', {'payload': payload});
    } catch (e) {
      debugPrint('Ошибка нативного моста печати: $e');
    }
  }

  static Future<void> sendRaw({
    required List<int> payload,
    required String protocolName,
  }) async {
    debugPrint(
      'LabelPrinterBridge[mobile]: protocol=$protocolName bytes=${payload.length}',
    );
    await sendRawPayload(utf8.decode(payload));
  }
}
