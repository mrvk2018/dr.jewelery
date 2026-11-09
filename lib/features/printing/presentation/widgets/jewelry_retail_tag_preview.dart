import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/won_format.dart';
import '../../domain/jewelry_label_data.dart';

/// Превью розничного ценника ~30×20 mm (экран + печать PWA).
class JewelryRetailTagPreview extends StatelessWidget {
  const JewelryRetailTagPreview({
    super.key,
    required this.data,
    this.scale = 4.0,
  });

  final JewelryLabelData data;
  final double scale;

  static const double tagWidthMm = 30;
  static const double tagHeightMm = 20;
  static const double mmToPx = 3.78;

  @override
  Widget build(BuildContext context) {
    final width = tagWidthMm * mmToPx * scale;
    final height = tagHeightMm * mmToPx * scale;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Ценник · ${tagWidthMm.toStringAsFixed(0)}×${tagHeightMm.toStringAsFixed(0)} mm',
          style: AppTypography.caption(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Container(
          width: width,
          height: height,
          padding: EdgeInsets.all(2.5 * scale),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.black87, width: 1.2),
            borderRadius: BorderRadius.circular(2 * scale),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                data.productName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 7 * scale,
                  fontWeight: FontWeight.w700,
                  height: 1.05,
                ),
              ),
              SizedBox(height: 1.5 * scale),
              Text(
                data.sku,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9.5 * scale,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  height: 1,
                ),
              ),
              SizedBox(height: 2 * scale),
              Expanded(child: _SkuBarcodeStrip(sku: data.sku, scale: scale)),
              SizedBox(height: 2 * scale),
              Text(
                data.probeSizeWeightLine,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 6.5 * scale, height: 1.05),
              ),
              Text(
                formatWon(data.priceKrw),
                style: TextStyle(
                  fontSize: 8 * scale,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SkuBarcodeStrip extends StatelessWidget {
  const _SkuBarcodeStrip({required this.sku, required this.scale});

  final String sku;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SkuBarcodePainter(sku),
      child: Center(
        child: Text(
          sku,
          style: TextStyle(
            fontSize: 5 * scale,
            fontFamily: 'monospace',
            letterSpacing: 1.2,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
}

class _SkuBarcodePainter extends CustomPainter {
  _SkuBarcodePainter(this.sku);

  final String sku;

  @override
  void paint(Canvas canvas, Size size) {
    final barPaint = Paint()..color = Colors.black;
    final hash = sku.codeUnits.fold<int>(0, (a, b) => a + b * 31 + b);
    var x = 0.0;
    const barWidth = 1.4;
    var seed = hash;
    while (x < size.width - barWidth) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      final wide = seed % 3 == 0;
      final h = size.height * (0.55 + (seed % 40) / 100);
      if (seed % 2 == 0) {
        canvas.drawRect(
          Rect.fromLTWH(x, size.height - h, wide ? barWidth * 1.6 : barWidth, h),
          barPaint,
        );
      }
      x += wide ? barWidth * 2.2 : barWidth * 1.5;
    }
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - 1, size.width, 1),
      barPaint..color = Colors.black26,
    );
  }

  @override
  bool shouldRepaint(covariant _SkuBarcodePainter oldDelegate) =>
      oldDelegate.sku != sku;
}
