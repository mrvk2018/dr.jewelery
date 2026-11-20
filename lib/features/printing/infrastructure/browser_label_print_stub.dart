import 'package:printing/printing.dart';

import '../application/label_print_service.dart';
import '../domain/jewelry_label_data.dart';
import '../domain/jewelry_label_layout.dart';
import '../domain/jewelry_label_pdf_builder.dart';

/// Mobile / desktop: PDF 12×60 mm + опционально сырой TSPL/ZPL.
Future<void> printJewelryLabelPlatform(
  JewelryLabelData data, {
  LabelPrintService? labelPrintService,
}) async {
  await printJewelryLabelsPlatform([data], labelPrintService: labelPrintService);
}

Future<void> printJewelryLabelsPlatform(
  List<JewelryLabelData> dataList, {
  LabelPrintService? labelPrintService,
}) async {
  if (dataList.isEmpty) return;

  final bytes = await JewelryLabelPdfBuilder.buildBytes(dataList);
  await Printing.layoutPdf(
    onLayout: (_) async => bytes,
    format: JewelryLabelLayout.pageFormat,
  );
}