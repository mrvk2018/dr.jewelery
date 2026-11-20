import 'dart:typed_data';

import 'package:printing/printing.dart';

import '../domain/jewelry_label_data.dart';
import '../domain/jewelry_label_layout.dart';
import '../domain/jewelry_label_pdf_builder.dart';

/// PWA: PDF 12×60 mm → системный диалог печати.
Future<void> printJewelryLabelPlatform(
  JewelryLabelData data, {
  dynamic labelPrintService,
}) async {
  await printJewelryLabelsPlatform([data], labelPrintService: labelPrintService);
}

Future<void> printJewelryLabelsPlatform(
  List<JewelryLabelData> dataList, {
  dynamic labelPrintService,
}) async {
  if (dataList.isEmpty) return;
  final bytes = await JewelryLabelPdfBuilder.buildBytes(dataList);
  await _printPdfBytes(bytes);
}

Future<void> _printPdfBytes(Uint8List bytes) async {
  await Printing.layoutPdf(
    onLayout: (_) async => bytes,
    format: JewelryLabelLayout.pageFormat,
  );
}