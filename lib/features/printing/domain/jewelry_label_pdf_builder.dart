import 'dart:typed_data';

import 'package:barcode/barcode.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/widgets.dart' as pw;

import 'jewelry_label_data.dart';
import 'jewelry_label_layout.dart';

/// PDF гантельки: 60 × 12 mm, по одной странице на изделие.
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
        pw.Widget textAt({
          required double xMm,
          required double yMm,
          required double widthMm,
          required String text,
          required double fontSize,
          pw.FontWeight weight = pw.FontWeight.normal,
          int maxLines = 2,
        }) {
          if (text.trim().isEmpty) return pw.SizedBox();
          return pw.Positioned(
            left: JewelryLabelLayout.mm(xMm),
            top: JewelryLabelLayout.mm(yMm),
            child: pw.SizedBox(
              width: JewelryLabelLayout.mm(widthMm),
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

        final frontX = JewelryLabelLayout.frontContentLeftMm;
        final frontW = JewelryLabelLayout.frontContentWidthMm;
        final backX = JewelryLabelLayout.backTextLeftMm;
        final backW = JewelryLabelLayout.backTextWidthMm;

        final frontY = JewelryLabelLayout.frontTextYMm(
          hasSubtype: data.subtype.isNotEmpty,
          hasSize: data.hasBackSize,
        );

        final children = <pw.Widget>[
          textAt(
            xMm: frontX,
            yMm: frontY.categoryY,
            widthMm: frontW,
            text: data.category,
            fontSize: JewelryLabelLayout.fontCategoryPt,
            weight: pw.FontWeight.bold,
            maxLines: 1,
          ),
          if (frontY.subtypeY != null)
            textAt(
              xMm: frontX,
              yMm: frontY.subtypeY!,
              widthMm: frontW,
              text: data.subtype,
              fontSize: JewelryLabelLayout.fontSubtypePt,
              weight: pw.FontWeight.bold,
              maxLines: 1,
            ),
          textAt(
            xMm: frontX,
            yMm: frontY.weightY,
            widthMm: frontW,
            text: data.weightLine,
            fontSize: JewelryLabelLayout.fontWeightPt,
            weight: pw.FontWeight.bold,
            maxLines: 1,
          ),
          if (frontY.sizeY != null)
            textAt(
              xMm: frontX,
              yMm: frontY.sizeY!,
              widthMm: frontW,
              text: data.frontSizeLine,
              fontSize: JewelryLabelLayout.fontSizePt,
              weight: pw.FontWeight.bold,
              maxLines: 1,
            ),
          textAt(
            xMm: frontX,
            yMm: frontY.priceY,
            widthMm: frontW,
            text: data.showroomPriceLine,
            fontSize: JewelryLabelLayout.fontPricePt,
            weight: pw.FontWeight.bold,
            maxLines: 1,
          ),
        ];

        final qrSize = JewelryLabelLayout.mm(JewelryLabelLayout.backQrSizeMm);

        children.add(
          pw.Positioned(
            left: JewelryLabelLayout.mm(JewelryLabelLayout.backQrLeftMm),
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

        final backDesc = data.backDescriptionLine;
        final backTextY = JewelryLabelLayout.backTextYMm(
          hasSize: data.hasBackSize,
          hasDescription: backDesc.isNotEmpty,
        );

        if (data.hasBackSize) {
          children.add(
            textAt(
              xMm: backX,
              yMm: backTextY.sizeY!,
              widthMm: backW,
              text: data.backSizeLine,
              fontSize: JewelryLabelLayout.fontBackSizePt,
              weight: pw.FontWeight.bold,
              maxLines: 1,
            ),
          );
        }

        children.add(
          textAt(
            xMm: backX,
            yMm: backTextY.insertsY,
            widthMm: backW,
            text: data.backInsertsLine,
            fontSize: JewelryLabelLayout.fontInsertsPt,
            maxLines: JewelryLabelLayout.backInsertsMaxLines,
          ),
        );

        if (backDesc.isNotEmpty && backTextY.descriptionY != null) {
          children.add(
            textAt(
              xMm: backX,
              yMm: backTextY.descriptionY!,
              widthMm: backW,
              text: backDesc,
              fontSize: JewelryLabelLayout.fontDescriptionPt,
              maxLines: JewelryLabelLayout.backDescriptionMaxLines,
            ),
          );
        }

        return pw.Stack(children: children);
      },
    );
  }
}