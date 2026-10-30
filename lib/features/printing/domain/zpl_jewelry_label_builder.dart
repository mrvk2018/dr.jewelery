import 'jewelry_label_data.dart';
import 'jewelry_label_layout.dart';

/// Генератор ZPL II для бирки 23×11,5 mm (UTF-8 через ^CI28).
abstract final class ZplJewelryLabelBuilder {
  static String build(JewelryLabelData data) {
    final buffer = StringBuffer()
      ..writeln('^XA')
      ..writeln('^CI28')
      ..writeln('^PW${JewelryLabelLayout.labelWidthDots}')
      ..writeln('^LL${JewelryLabelLayout.labelHeightDots}')
      ..writeln('^LH0,0');

    _textLine(
      buffer,
      y: JewelryLabelLayout.line1Y,
      text: _escapeZpl(data.productName),
      height: JewelryLabelLayout.fontHeightPrimary,
    );
    _textLine(
      buffer,
      y: JewelryLabelLayout.line2Y,
      text: _escapeZpl(data.sku),
      height: JewelryLabelLayout.fontHeightSecondary,
    );
    _textLine(
      buffer,
      y: JewelryLabelLayout.line3Y,
      text: _escapeZpl(data.probeSizeWeightLine),
      height: JewelryLabelLayout.fontHeightSecondary,
    );
    _textLine(
      buffer,
      y: JewelryLabelLayout.line4Y,
      text: _escapeZpl(data.priceLine),
      height: JewelryLabelLayout.fontHeightSecondary,
    );

    buffer.writeln('^XZ');
    return buffer.toString();
  }

  static void _textLine(
    StringBuffer buffer, {
    required int y,
    required String text,
    required int height,
  }) {
    buffer.writeln(
      '^FO${JewelryLabelLayout.textOriginXDots},$y'
      '^A0N,$height,$height'
      '^FD$text^FS',
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
