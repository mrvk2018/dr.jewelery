import 'jewelry_label_data.dart';
import 'jewelry_label_layout.dart';

/// TSPL для гантельки 12×60 mm.
abstract final class TsplJewelryLabelBuilder {
  static String build(JewelryLabelData data) {
    final buffer = StringBuffer()
      ..writeln(
        'SIZE ${JewelryLabelLayout.labelWidthMm} mm, '
        '${JewelryLabelLayout.labelHeightMm} mm',
      )
      ..writeln('GAP 2 mm, 0 mm')
      ..writeln('DIRECTION 1')
      ..writeln('CODEPAGE UTF-8')
      ..writeln('CLS');

    var y = 30;
    const step = 55;

    _text(buffer, y, data.category);
    y += step;
    if (data.subtype.isNotEmpty) {
      _text(buffer, y, data.subtype);
      y += step;
    }
    _text(buffer, y, data.weightLine);
    y += step;
    if (data.sizeLine.isNotEmpty) {
      _text(buffer, y, data.sizeLine);
      y += step;
    }
    _text(buffer, y, data.showroomPriceLine);

    buffer.writeln('PRINT 1,1');
    return buffer.toString();
  }

  static void _text(StringBuffer buffer, int yDots, String text) {
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