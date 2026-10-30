import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/jewelry_label_data.dart';
import '../../domain/jewelry_label_layout.dart';

/// Интерактивное превью бирки 23×11,5 mm (Web + Android).
class JewelryLabelPreview extends StatelessWidget {
  const JewelryLabelPreview({
    super.key,
    required this.data,
    this.scale = 3.5,
  });

  final JewelryLabelData data;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final width = JewelryLabelLayout.labelWidthDots * scale;
    final height = JewelryLabelLayout.labelHeightDots * scale;
    final deadWidth =
        JewelryLabelLayout.deadZoneWidthMm / JewelryLabelLayout.labelWidthMm * width;
    final textLeft =
        JewelryLabelLayout.textOriginXDots / JewelryLabelLayout.labelWidthDots * width;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Превью бирки · 23×11,5 mm · 300 DPI',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 8),
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.border, width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: deadWidth,
                child: ColoredBox(
                  color: Colors.grey.shade400,
                  child: Center(
                    child: RotatedBox(
                      quarterTurns: 3,
                      child: Text(
                        'отверстие',
                        style: TextStyle(
                          fontSize: 8 * scale / 3,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                left: textLeft,
                child: Padding(
                  padding: EdgeInsets.only(right: 4 * scale / 3),
                  child: _PreviewTextColumn(data: data, scale: scale),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PreviewTextColumn extends StatelessWidget {
  const _PreviewTextColumn({
    required this.data,
    required this.scale,
  });

  final JewelryLabelData data;
  final double scale;

  double _yToTop(int yDots) =>
      yDots / JewelryLabelLayout.labelHeightDots *
      JewelryLabelLayout.labelHeightDots *
      scale;

  @override
  Widget build(BuildContext context) {
    final mono = TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Courier', 'Roboto Mono', 'monospace'],
      fontSize: 9 * scale / 3.5,
      height: 1.05,
      color: AppColors.textPrimary,
    );

    return Stack(
      children: [
        _line(_yToTop(JewelryLabelLayout.line1Y), data.productName, mono, bold: true),
        _line(_yToTop(JewelryLabelLayout.line2Y), data.sku, mono),
        _line(_yToTop(JewelryLabelLayout.line3Y), data.probeSizeWeightLine, mono),
        _line(_yToTop(JewelryLabelLayout.line4Y), data.priceLine, mono),
      ],
    );
  }

  Widget _line(double top, String text, TextStyle style, {bool bold = false}) {
    return Positioned(
      left: 0,
      right: 0,
      top: top,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: bold ? style.copyWith(fontWeight: FontWeight.w700) : style,
      ),
    );
  }
}
