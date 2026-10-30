import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/jewelry_label_data.dart';
import '../domain/jewelry_label_layout.dart';
import '../domain/tspl_jewelry_label_builder.dart';
import '../domain/zpl_jewelry_label_builder.dart';
import '../infrastructure/label_printer_bridge.dart';

/// Оркестратор печати бирки: билдеры + платформенный мост (без native в Фазе 1).
class LabelPrintService {
  const LabelPrintService({
    this.protocol = LabelPrinterProtocol.zpl,
  });

  final LabelPrinterProtocol protocol;

  String buildCommands(JewelryLabelData data) {
    return switch (protocol) {
      LabelPrinterProtocol.zpl => ZplJewelryLabelBuilder.build(data),
      LabelPrinterProtocol.tspl => TsplJewelryLabelBuilder.build(data),
    };
  }

  Future<void> printLabel(JewelryLabelData data) async {
    final commands = buildCommands(data);
    final bytes = utf8.encode(commands);

    if (kIsWeb) {
      debugPrint(
        'LabelPrintService[web]: preview-only / log (${protocol.name}) '
        '${bytes.length} bytes',
      );
      debugPrint(commands);
      return;
    }

    await LabelPrinterBridge.sendRaw(
      payload: bytes,
      protocolName: protocol.name,
    );
  }

  Future<void> printFromProductMap(Map<String, dynamic> product) {
    return printLabel(JewelryLabelData.fromProductMap(product));
  }
}
