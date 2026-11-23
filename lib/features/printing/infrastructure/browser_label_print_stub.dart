import '../application/label_print_service.dart';
import '../domain/jewelry_label_data.dart';

/// Mobile / desktop: PDF 60×12 mm через системный диалог печати.
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
  final service = labelPrintService ?? const LabelPrintService();
  await service.printSystemPdfBatch(dataList);
}