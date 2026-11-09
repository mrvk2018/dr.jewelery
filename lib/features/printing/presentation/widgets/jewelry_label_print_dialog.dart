import 'package:flutter/material.dart';

import '../../../../core/theme/app_typography.dart';
import '../../application/label_print_service.dart';
import '../../domain/jewelry_label_data.dart';
import '../../domain/jewelry_label_layout.dart';
import '../../infrastructure/browser_label_print.dart';
import 'jewelry_label_preview.dart';
import 'jewelry_retail_tag_preview.dart';

/// Предпросмотр ценника + печать (Web: диалог браузера, иначе TSPL/ZPL).
class JewelryLabelPrintDialog extends StatelessWidget {
  const JewelryLabelPrintDialog({
    super.key,
    required this.productRow,
    this.titleSuffix,
  });

  final Map<String, dynamic> productRow;
  final String? titleSuffix;

  static Future<bool?> show(
    BuildContext context, {
    required Map<String, dynamic> productRow,
    String? titleSuffix,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => JewelryLabelPrintDialog(
        productRow: productRow,
        titleSuffix: titleSuffix,
      ),
    );
  }

  static Future<void> showAndPrint(
    BuildContext context, {
    required Map<String, dynamic> productRow,
    String? titleSuffix,
  }) async {
    final confirmed = await show(
      context,
      productRow: productRow,
      titleSuffix: titleSuffix,
    );
    if (confirmed != true || !context.mounted) return;

    final data = JewelryLabelData.fromProductMap(productRow);
    await printJewelryLabelPlatform(
      data,
      labelPrintService: const LabelPrintService(
        protocol: LabelPrinterProtocol.tspl,
      ),
    );
  }

  JewelryLabelData get _data => JewelryLabelData.fromProductMap(productRow);

  @override
  Widget build(BuildContext context) {
    final data = _data;
    final sku = data.sku;
    final suffix = titleSuffix;

    return AlertDialog(
      title: Text(
        suffix != null ? '$suffix · $sku' : 'Печать ценника · $sku',
        style: AppTypography.heading(fontSize: 18),
      ),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              JewelryRetailTagPreview(data: data),
              const SizedBox(height: 16),
              JewelryLabelPreview(data: data, scale: 2.8),
              const SizedBox(height: 8),
              Text(
                'Термобирка 23×11,5 mm — для принтера TSPL; '
                'розничный ценник 30×20 mm — через печать браузера.',
                style: AppTypography.productMeta(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.print_outlined, size: 20),
          label: const Text('Печать'),
        ),
      ],
    );
  }
}
