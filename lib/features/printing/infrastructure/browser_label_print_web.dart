import '../application/label_print_service.dart';
import '../domain/jewelry_label_data.dart';

/// PWA: PDF 60×12 mm → системный диалог печати (`Printing.layoutPdf`).
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
  final LabelPrintService service = labelPrintService is LabelPrintService
      ? labelPrintService
      : const LabelPrintService();
  await service.printSystemPdfBatch(dataList);
}