import 'package:pdf/pdf.dart';

/// Вертикальная гантелька 12 × 60 mm (лицевая зона · перемычка · оборот).
abstract final class JewelryLabelLayout {
  static const double labelWidthMm = 12;
  static const double labelHeightMm = 60;

  static const double earMarginHorizontalMm = 0.8;
  static const double contentWidthMm =
      labelWidthMm - 2 * earMarginHorizontalMm; // 10.4

  /// Линии отреза ножницами (2 mm буфер до рабочих зон).
  static const double topCutLineMm = 22;
  static const double bottomCutLineMm = 38;

  static const double frontEarWorkTopMm = 1.0;
  static const double frontEarWorkBottomMm = 20.0;

  static const double bridgeTopMm = 20.0;
  static const double bridgeBottomMm = 40.0;

  static const double backEarWorkTopMm = 40.0;
  static const double backEarWorkBottomMm = 59.0;

  static double mm(double value) => value * PdfPageFormat.mm;

  static PdfPageFormat get pageFormat => PdfPageFormat(
        mm(labelWidthMm),
        mm(labelHeightMm),
        marginAll: 0,
      );

  /// Лицевая сторона (5 строк, сверху вниз, pt).
  static const double frontCategoryYmm = 1.2;
  static const double frontSubtypeYmm = 4.8;
  static const double frontWeightYmm = 8.4;
  static const double frontSizeYmm = 12.0;
  static const double frontPriceYmm = 15.8;

  static const double fontCategoryPt = 6.5;
  static const double fontSubtypePt = 6.0;
  static const double fontWeightPt = 6.5;
  static const double fontSizePt = 6.0;
  static const double fontPricePt = 7.0;

  /// Оборот: QR 9×9 mm, затем вставки, описание.
  static const double backQrSizeMm = 9.0;
  static const double backQrTopMm = 41.0;
  static const double backInsertsYmm = 51.0;
  static const double backDescriptionYmm = 54.0;
  static const double fontInsertsPt = 6.0;
  static const double fontDescriptionPt = 5.5;

  // Legacy 300 DPI термопринтер (частота использования снижается — PDF основной).
  static const int dpi = 300;
  static const double dotsPerMm = dpi / 25.4;
  static const int labelWidthDots = 142;
  static const int labelHeightDots = 709;
  static const int textOriginXDots = 94;
}

enum LabelPrinterProtocol {
  zpl,
  tspl,
}