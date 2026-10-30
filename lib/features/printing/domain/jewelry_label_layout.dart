/// Геометрия ювелирной бирки 23×11,5 mm @ 300 DPI (термотransfer).
abstract final class JewelryLabelLayout {
  static const double labelWidthMm = 23;
  static const double labelHeightMm = 11.5;
  static const int dpi = 300;

  /// 300 DPI → dots/mm.
  static const double dotsPerMm = dpi / 25.4;

  static const int labelWidthDots = 271;
  static const int labelHeightDots = 136;

  static const double deadZoneWidthMm = 5;
  static const int deadZoneWidthDots = 59;

  /// Начало полезной области (люфт от мёртвой зоны).
  static const int textOriginXDots = 64;

  static const int printableWidthDots = labelWidthDots - textOriginXDots;

  static const int line1Y = 15;
  static const int line2Y = 45;
  static const int line3Y = 75;
  static const int line4Y = 105;

  static const int fontHeightPrimary = 20;
  static const int fontHeightSecondary = 18;
}

enum LabelPrinterProtocol {
  zpl,
  tspl,
}
