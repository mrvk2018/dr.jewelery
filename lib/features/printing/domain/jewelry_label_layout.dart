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

  /// Лицо: Y 0.6–7.9 mm (фиксированная сетка, без «дыр» при пропусках).
  static const List<double> frontLineYsMm = [0.6, 2.4, 4.2, 6.0, 7.9];

  static const double fontCategoryPt = 5.3;
  static const double fontSubtypePt = 4.9;
  static const double fontWeightPt = 5.3;
  static const double fontSizePt = 5.3;
  static const double fontPricePt = 6.0;

  /// Межстрочный коэффициент (Flutter `height` / плотный PDF).
  static const double textLineHeight = 1.0;
  static const double pdfLineSpacing = 0;

  /// Оборот: QR 8×8 @ 41.2×1.8 mm; текст 49.8–58.5 mm (ширина 8.7 mm).
  static const double backQrLeftMm = 41.2;
  static const double backQrTopMm = 1.8;
  static const double backQrSizeMm = 8.0;

  static const double backTextLeftMm = 49.8;
  static const double backTextRightMm = 58.5;
  static const double backTextWidthMm = backTextRightMm - backTextLeftMm;

  static const double backSizeYMm = 0.7;
  static const double backInsertsYMmWithSize = 2.7;
  static const double backInsertsYMmNoSize = 0.7;
  static const double backDescriptionYMmWithSize = 7.3;
  static const double backDescriptionYMmNoSize = 5.0;

  static const double fontBackSizePt = 5.3;
  static const double fontInsertsPt = 4.6;
  static const int backInsertsMaxLines = 2;
  static const int backInsertsMaxChars = 22;
  static const double fontDescriptionPt = 4.6;
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
    final ctSplit = RegExp(
      r'^(.+?)(\s+[\d.,]+\s*ct)\s*$',
      caseSensitive: false,
    ).firstMatch(t);
    if (ctSplit != null && t.length > 16) {
      final name = ctSplit.group(1)!.trim();
      final carat = ctSplit.group(2)!.trim();
      if (name.length <= backInsertsMaxChars) {
        return '$name\n$carat';
      }
    }
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
    var idx = 0;
    double nextY() => frontLineYsMm[idx++];

    final categoryY = nextY();

    double? subtypeY;
    if (hasSubtype) {
      subtypeY = nextY();
    }

    final weightY = nextY();

    double? sizeY;
    if (hasSize) {
      sizeY = nextY();
    }

    final priceY = nextY();
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
    final double? sizeY = hasSize ? backSizeYMm : null;
    final insertsY =
        hasSize ? backInsertsYMmWithSize : backInsertsYMmNoSize;
    final double? descriptionY = hasDescription
        ? (hasSize ? backDescriptionYMmWithSize : backDescriptionYMmNoSize)
        : null;
    return (
      sizeY: sizeY,
      insertsY: insertsY,
      descriptionY: descriptionY,
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