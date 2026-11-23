import 'package:pdf/pdf.dart';

/// Горизонтальная гантелька 60 × 12 mm (лицо · перемычка · оборот по оси X).
abstract final class JewelryLabelLayout {
  static const double labelWidthMm = 60.0;
  static const double labelHeightMm = 12.0;

  static const double earInsetMm = 0.8;

  /// Линии отреза (вертикальные, между ушками и перемычкой).
  static const double leftCutLineMm = 20.0;
  static const double rightCutLineMm = 40.0;

  static const double frontEarLeftMm = 1.0;
  static const double frontEarRightMm = 20.0;
  static const double bridgeLeftMm = 20.0;
  static const double bridgeRightMm = 40.0;
  static const double backEarLeftMm = 40.0;
  static const double backEarRightMm = 59.0;

  static const double frontContentLeftMm = frontEarLeftMm + earInsetMm;
  static const double frontContentWidthMm =
      frontEarRightMm - frontEarLeftMm - 2 * earInsetMm;

  static double mm(double value) => value * PdfPageFormat.mm;

  static PdfPageFormat get pageFormat => PdfPageFormat(
        mm(labelWidthMm),
        mm(labelHeightMm),
        marginAll: 0,
      );

  /// Лицо: X 1–20 mm, компактно по Y (высота 12 mm).
  static const double frontCategoryYmm = 0.3;
  static const double frontSubtypeYmm = 2.3;
  static const double frontWeightYmm = 4.5;
  static const double frontSizeYmm = 6.5;
  static const double frontPriceYmm = 8.6;

  static const double fontCategoryPt = 6.0;
  static const double fontSubtypePt = 5.5;
  static const double fontWeightPt = 6.0;
  static const double fontSizePt = 5.5;
  static const double fontPricePt = 6.5;

  /// Оборот: QR 8×8 слева, текст справа (X 49.5–58.8 mm).
  static const double backQrLeftMm = 40.8;
  static const double backQrTopMm = 2.0;
  static const double backQrSizeMm = 8.0;

  static const double backTextLeftMm = 49.5;
  static const double backTextRightMm = 58.8;
  static const double backTextWidthMm = backTextRightMm - backTextLeftMm;

  static const double backTextFirstLineYMm = 2.0;
  static const double backTextLineStepMm = 2.05;

  static const double fontInsertsPt = 5.5;
  static const double fontDescriptionPt = 5.0;
  static const int backDescriptionMaxChars = 20;
  static const int backDescriptionMaxLines = 2;

  static String clampBackDescription(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    if (t.length <= backDescriptionMaxChars) return t;
    return '${t.substring(0, backDescriptionMaxChars)}…';
  }

  /// Y (mm) строк текста справа от QR.
  static ({
    double? sizeY,
    double insertsY,
    double? descriptionY,
  }) backTextYMm({
    required bool hasSize,
    required bool hasDescription,
  }) {
    var y = backTextFirstLineYMm;
    double? sizeY;
    if (hasSize) {
      sizeY = y;
      y += backTextLineStepMm;
    }
    final insertsY = y;
    y += backTextLineStepMm;
    return (
      sizeY: sizeY,
      insertsY: insertsY,
      descriptionY: hasDescription ? y : null,
    );
  }

  // Legacy 300 DPI термопринтер (SIZE берёт [labelWidthMm] × [labelHeightMm]).
  static const int dpi = 300;
  static const double dotsPerMm = dpi / 25.4;
  static const int labelWidthDots = 709;
  static const int labelHeightDots = 142;
  static const int textOriginXDots = 21;
}

enum LabelPrinterProtocol {
  zpl,
  tspl,
}