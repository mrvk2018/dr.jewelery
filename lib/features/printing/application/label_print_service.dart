import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';

import '../domain/jewelry_label_data.dart';
import '../domain/jewelry_label_layout.dart';
import '../domain/jewelry_label_pdf_builder.dart';
import '../domain/tspl_jewelry_label_builder.dart';
import '../domain/zpl_jewelry_label_builder.dart';
import '../infrastructure/label_printer_bridge.dart';

/// Оркестратор печати бирки: PDF + TSPL/ZPL.
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

  Future<Uint8List> buildPdfBytes(JewelryLabelData data) =>
      JewelryLabelPdfBuilder.buildSingle(data);

  Future<Uint8List> buildPdfBytesBatch(List<JewelryLabelData> items) =>
      JewelryLabelPdfBuilder.buildBytes(items);

  /// Системный диалог печати PDF (браузер / ОС), формат 60×12 mm.
  Future<void> printSystemPdf(JewelryLabelData data) =>
      printSystemPdfBatch([data]);

  Future<void> printSystemPdfBatch(List<JewelryLabelData> items) async {
    if (items.isEmpty) return;
    final bytes = await buildPdfBytesBatch(items);
    final name = items.length == 1
        ? 'jewelry-label-${items.first.sku}'
        : 'jewelry-labels-${items.length}';
    await Printing.layoutPdf(
      onLayout: (_) async => bytes,
      format: JewelryLabelLayout.pageFormat,
      name: name,
    );
  }

  /// Сырой TSPL/ZPL на нативный мост; на Web — только PDF через [printSystemPdf].
  Future<void> printLabel(JewelryLabelData data) async {
    if (kIsWeb) {
      await printSystemPdf(data);
      return;
    }

    final commands = buildCommands(data);
    final bytes = utf8.encode(commands);

    await LabelPrinterBridge.sendRaw(
      payload: bytes,
      protocolName: protocol.name,
    );
  }

  Future<void> printFromProductMap(Map<String, dynamic> product) {
    return printLabel(JewelryLabelData.fromProductMap(product));
  }
}