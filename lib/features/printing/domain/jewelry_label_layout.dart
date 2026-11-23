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

  /// Калибровка печати: текст внутри белого ушка (3.8 … 19.3 mm).
  static const double frontContentLeftMm = 3.8;
  static const double frontContentWidthMm = 15.5;

  static double mm(double value) => value * PdfPageFormat.mm;

  static PdfPageFormat get pageFormat => PdfPageFormat(
        mm(labelWidthMm),
        mm(labelHeightMm),
        marginAll: 0,
      );

  /// Лицо: Y 0.8–7.8 mm (5 строк с шагом 1.6 mm, без «дыр» при пропусках).
  static const double frontFirstLineYMm = 0.8;
  static const double frontLineStepMm = 1.6;

  static const double fontCategoryPt = 6.5;
  static const double fontSubtypePt = 6.5;
  static const double fontWeightPt = 7.0;
  static const double fontSizePt = 7.0;
  static const double fontPricePt = 8.0;

  /// Оборот: QR 8×8 @ 41.2×1.8 mm; текст 49.8–58.5 mm (ширина 8.7 mm).
  static const double backQrLeftMm = 41.2;
  static const double backQrTopMm = 1.8;
  static const double backQrSizeMm = 8.0;

  static const double backTextLeftMm = 49.8;
  static const double backTextRightMm = 58.5;
  static const double backTextWidthMm = backTextRightMm - backTextLeftMm;

  static const double backTextFirstLineYMm = 0.8;
  static const double backSizeLineStepMm = 2.0;
  static const double backInsertsBlockHeightMm = 3.85;
  static const double backDescriptionBlockHeightMm = 3.6;

  static const double fontBackSizePt = 6.5;
  static const double fontInsertsPt = 6.0;
  static const int backInsertsMaxLines = 2;
  static const int backInsertsMaxChars = 22;
  static const double fontDescriptionPt = 5.8;
  static const int backDescriptionMaxChars = 20;
  static const int backDescriptionMaxLines = 2;

  static String clampBackDescription(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    if (t.length <= backDescriptionMaxChars) return t;
    return '${t.substring(0, backDescriptionMaxChars)}…';
  }

  static String clampBackInserts(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return 'Без камней';
    if (t.length <= backInsertsMaxChars) return t;
    return '${t.substring(0, backInsertsMaxChars)}…';
  }

  /// Y (mm) строк лицевого ушка; пропущенные поля не оставляют пустых интервалов.
  static ({
    double categoryY,
    double? subtypeY,
    double weightY,
    double? sizeY,
    double priceY,
  }) frontTextYMm({
    required bool hasSubtype,
    required bool hasSize,
  }) {
    var y = frontFirstLineYMm;
    final categoryY = y;
    y += frontLineStepMm;

    double? subtypeY;
    if (hasSubtype) {
      subtypeY = y;
      y += frontLineStepMm;
    }

    final weightY = y;
    y += frontLineStepMm;

    double? sizeY;
    if (hasSize) {
      sizeY = y;
      y += frontLineStepMm;
    }

    final priceY = y;
    return (
      categoryY: categoryY,
      subtypeY: subtypeY,
      weightY: weightY,
      sizeY: sizeY,
      priceY: priceY,
    );
  }

  /// Y (mm) блоков текста справа от QR (0.8–11.2 mm).
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
      y += backSizeLineStepMm;
    }
    final insertsY = y;
    y += backInsertsBlockHeightMm;
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
  static const int textOriginXDots = 45;
}

enum LabelPrinterProtocol {
  zpl,
  tspl,
}