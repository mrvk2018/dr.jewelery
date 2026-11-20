import 'dart:typed_data';

import 'package:barcode/barcode.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

import 'jewelry_label_data.dart';
import 'jewelry_label_layout.dart';

/// PDF гантельки: 12 × 60 mm, по одной странице на изделие.
abstract final class JewelryLabelPdfBuilder {
  static pw.Font? _notoRegular;

  static Future<pw.Font> _font() async {
    _notoRegular ??= pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    return _notoRegular!;
  }

  static Future<Uint8List> buildBytes(List<JewelryLabelData> labels) async {
    final font = await _font();
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: font, bold: font),
    );
    for (final data in labels) {
      doc.addPage(_page(data, font));
    }
    return doc.save();
  }

  static Future<Uint8List> buildSingle(JewelryLabelData data) =>
      buildBytes([data]);

  static pw.Page _page(JewelryLabelData data, pw.Font font) {
    return pw.Page(
      pageFormat: JewelryLabelLayout.pageFormat,
      margin: pw.EdgeInsets.zero,
      build: (context) {
        final x = JewelryLabelLayout.mm(JewelryLabelLayout.earMarginHorizontalMm);
        final w = JewelryLabelLayout.mm(JewelryLabelLayout.contentWidthMm);

        pw.Widget textAt({
          required double yMm,
          required String text,
          required double fontSize,
          pw.FontWeight weight = pw.FontWeight.normal,
          int maxLines = 2,
        }) {
          if (text.trim().isEmpty) return pw.SizedBox();
          return pw.Positioned(
            left: x,
            top: JewelryLabelLayout.mm(yMm),
            child: pw.SizedBox(
              width: w,
              child: pw.Text(
                text,
                style: pw.TextStyle(
                  font: font,
                  fontSize: fontSize,
                  fontWeight: weight,
                  lineSpacing: 0.5,
                ),
                maxLines: maxLines,
                overflow: pw.TextOverflow.clip,
              ),
            ),
          );
        }

        final children = <pw.Widget>[
          textAt(
            yMm: JewelryLabelLayout.frontCategoryYmm,
            text: data.category,
            fontSize: JewelryLabelLayout.fontCategoryPt,
            weight: pw.FontWeight.bold,
          ),
          if (data.subtype.isNotEmpty)
            textAt(
              yMm: JewelryLabelLayout.frontSubtypeYmm,
              text: data.subtype,
              fontSize: JewelryLabelLayout.fontSubtypePt,
            ),
          textAt(
            yMm: JewelryLabelLayout.frontWeightYmm,
            text: data.weightLine,
            fontSize: JewelryLabelLayout.fontWeightPt,
            weight: pw.FontWeight.bold,
          ),
          if (data.sizeLine.isNotEmpty)
            textAt(
              yMm: JewelryLabelLayout.frontSizeYmm,
              text: data.sizeLine,
              fontSize: JewelryLabelLayout.fontSizePt,
            ),
          textAt(
            yMm: JewelryLabelLayout.frontPriceYmm,
            text: data.showroomPriceLine,
            fontSize: JewelryLabelLayout.fontPricePt,
            weight: pw.FontWeight.bold,
          ),
        ];

        final qrSize = JewelryLabelLayout.mm(JewelryLabelLayout.backQrSizeMm);
        final qrLeft =
            (JewelryLabelLayout.mm(JewelryLabelLayout.labelWidthMm) - qrSize) / 2;

        children.add(
          pw.Positioned(
            left: qrLeft,
            top: JewelryLabelLayout.mm(JewelryLabelLayout.backQrTopMm),
            child: pw.SizedBox(
              width: qrSize,
              height: qrSize,
              child: pw.BarcodeWidget(
                barcode: Barcode.qrCode(),
                data: data.qrPayload,
                width: qrSize,
                height: qrSize,
                drawText: false,
              ),
            ),
          ),
        );

        children.add(
          textAt(
            yMm: JewelryLabelLayout.backInsertsYmm,
            text: data.insertsLine,
            fontSize: JewelryLabelLayout.fontInsertsPt,
            maxLines: 1,
          ),
        );

        if (data.descriptionLine.isNotEmpty) {
          children.add(
            textAt(
              yMm: JewelryLabelLayout.backDescriptionYmm,
              text: data.descriptionLine,
              fontSize: JewelryLabelLayout.fontDescriptionPt,
              maxLines: 3,
            ),
          );
        }

        return pw.Stack(children: children);
      },
    );
  }
}