import 'jewelry_label_data.dart';
import 'jewelry_label_layout.dart';

/// Генератор TSPL (TSC) для бирки 23×11,5 mm.
abstract final class TsplJewelryLabelBuilder {
  static String build(JewelryLabelData data) {
    final buffer = StringBuffer()
      ..writeln('SIZE ${JewelryLabelLayout.labelWidthMm} mm, '
          '${JewelryLabelLayout.labelHeightMm} mm')
      ..writeln('GAP 2 mm, 0 mm')
      ..writeln('DIRECTION 1')
      ..writeln('CODEPAGE UTF-8')
      ..writeln('CLS');

    _textLine(buffer, JewelryLabelLayout.line1Y, data.productName);
    _textLine(buffer, JewelryLabelLayout.line2Y, data.sku);
    _textLine(buffer, JewelryLabelLayout.line3Y, data.probeSizeWeightLine);
    _textLine(buffer, JewelryLabelLayout.line4Y, data.priceLine);

    buffer.writeln('PRINT 1,1');
    return buffer.toString();
  }

  static void _textLine(StringBuffer buffer, int yDots, String text) {
    final escaped = _escapeTspl(text);
    buffer.writeln(
      'TEXT ${JewelryLabelLayout.textOriginXDots},$yDots,'
      '"0",0,1,1,"$escaped"',
    );
  }

  static String _escapeTspl(String raw) {
    return raw.replaceAll('"', "'").replaceAll('\n', ' ').trim();
  }
}
