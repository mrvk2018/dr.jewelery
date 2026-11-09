import 'package:flutter/foundation.dart';

import '../application/label_print_service.dart';
import '../domain/jewelry_label_data.dart';

/// Mobile / desktop native: сырой TSPL/ZPL через [LabelPrintService].
Future<void> printJewelryLabelPlatform(
  JewelryLabelData data, {
  LabelPrintService? labelPrintService,
}) async {
  final service = labelPrintService ?? const LabelPrintService();
  if (kIsWeb) {
    debugPrint(
      'browser_label_print_stub: web без dart:html — лог этикетки ${data.sku}',
    );
    return;
  }
  await service.printLabel(data);
}
