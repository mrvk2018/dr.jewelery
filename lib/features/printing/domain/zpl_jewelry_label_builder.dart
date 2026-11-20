import 'jewelry_label_data.dart';
import 'jewelry_label_layout.dart';

/// ZPL для гантельки 12×60 mm (лицевая полоса, UTF-8 ^CI28).
abstract final class ZplJewelryLabelBuilder {
  static String build(JewelryLabelData data) {
    final buffer = StringBuffer()
      ..writeln('^XA')
      ..writeln('^CI28')
      ..writeln('^PW${JewelryLabelLayout.labelWidthDots}')
      ..writeln('^LL${JewelryLabelLayout.labelHeightDots}')
      ..writeln('^LH0,0');

    var y = 30;
    const step = 55;
    const h = 18;

    _line(buffer, y, data.category, h);
    y += step;
    if (data.subtype.isNotEmpty) {
      _line(buffer, y, data.subtype, h - 2);
      y += step;
    }
    _line(buffer, y, data.weightLine, h);
    y += step;
    if (data.sizeLine.isNotEmpty) {
      _line(buffer, y, data.sizeLine, h - 2);
      y += step;
    }
    _line(buffer, y, data.showroomPriceLine, h);

    buffer.writeln('^XZ');
    return buffer.toString();
  }

  static void _line(StringBuffer buffer, int y, String text, int height) {
    buffer.writeln(
      '^FO${JewelryLabelLayout.textOriginXDots},$y'
      '^A0N,$height,$height'
      '^FD${_escapeZpl(text)}^FS',
    );
  }

  static String _escapeZpl(String raw) {
    return raw
        .replaceAll('^', ' ')
        .replaceAll('~', ' ')
        .replaceAll('\n', ' ')
        .trim();
  }
}