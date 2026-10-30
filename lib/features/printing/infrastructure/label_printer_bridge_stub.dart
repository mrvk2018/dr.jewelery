import 'package:flutter/foundation.dart';

/// Web / desktop: без dart:io, без MethodChannel (Фаза 1).
abstract final class LabelPrinterBridge {
  static Future<void> sendRaw({
    required List<int> payload,
    required String protocolName,
  }) async {
    debugPrint(
      'LabelPrinterBridge[stub]: protocol=$protocolName '
      'bytes=${payload.length}',
    );
  }
}
