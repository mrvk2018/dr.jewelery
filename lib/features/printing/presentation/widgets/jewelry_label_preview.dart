import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/jewelry_label_data.dart';
import '../../domain/jewelry_label_layout.dart';

/// Превью гантельки 12×60 mm (два ушка + перемычка).
class JewelryLabelPreview extends StatelessWidget {
  const JewelryLabelPreview({
    super.key,
    required this.data,
    this.scale = 6.0,
    this.showCutGuides = true,
  });

  final JewelryLabelData data;
  final double scale;
  final bool showCutGuides;

  static const double _mmToPreviewPx = 3.2;

  @override
  Widget build(BuildContext context) {
    final width = JewelryLabelLayout.labelWidthMm * _mmToPreviewPx * scale;
    final height = JewelryLabelLayout.labelHeightMm * _mmToPreviewPx * scale;
    double mmPx(double mm) => mm * _mmToPreviewPx * scale;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Гантелька · 12×60 mm (лицо сверху)',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: 8),
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: AppColors.border),
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
              if (showCutGuides) ...[
                Positioned(
                  left: 0,
                  right: 0,
                  top: mmPx(JewelryLabelLayout.topCutLineMm),
                  child: _cutGuide(),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: mmPx(JewelryLabelLayout.bottomCutLineMm),
                  child: _cutGuide(),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: mmPx(JewelryLabelLayout.bridgeTopMm),
                  height: mmPx(
                    JewelryLabelLayout.bridgeBottomMm -
                        JewelryLabelLayout.bridgeTopMm,
                  ),
                  child: ColoredBox(color: Colors.grey.shade100),
                ),
              ],
              Positioned(
                left: mmPx(JewelryLabelLayout.earMarginHorizontalMm),
                top: mmPx(JewelryLabelLayout.frontCategoryYmm),
                width: mmPx(JewelryLabelLayout.contentWidthMm),
                child: _FrontEarColumn(data: data, scale: scale),
              ),
              Positioned(
                left: 0,
                width: width,
                top: mmPx(JewelryLabelLayout.backQrTopMm - 1),
                child: _BackEarColumn(data: data, scale: scale, mmPx: mmPx),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _cutGuide() => LayoutBuilder(
        builder: (context, constraints) {
          return CustomPaint(
            size: Size(constraints.maxWidth, 1),
            painter: _DashedLinePainter(),
          );
        },
      );
}

class _FrontEarColumn extends StatelessWidget {
  const _FrontEarColumn({required this.data, required this.scale});

  final JewelryLabelData data;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(
      fontSize: 6.5 * scale / 6,
      height: 1.05,
      color: AppColors.textPrimary,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(data.category, style: base.copyWith(fontWeight: FontWeight.w700)),
        if (data.subtype.isNotEmpty) ...[
          SizedBox(height: 1.5 * scale / 6),
          Text(data.subtype, style: base.copyWith(fontSize: 6 * scale / 6)),
        ],
        SizedBox(height: 1.5 * scale / 6),
        Text(
          data.weightLine,
          style: base.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 6.5 * scale / 6,
          ),
        ),
        if (data.sizeLine.isNotEmpty) ...[
          SizedBox(height: 1.5 * scale / 6),
          Text(data.sizeLine, style: base.copyWith(fontSize: 6 * scale / 6)),
        ],
        SizedBox(height: 1.5 * scale / 6),
        Text(
          data.showroomPriceLine,
          style: base.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 7 * scale / 6,
          ),
        ),
      ],
    );
  }
}

class _BackEarColumn extends StatelessWidget {
  const _BackEarColumn({
    required this.data,
    required this.scale,
    required this.mmPx,
  });

  final JewelryLabelData data;
  final double scale;
  final double Function(double mm) mmPx;

  @override
  Widget build(BuildContext context) {
    final qr = mmPx(JewelryLabelLayout.backQrSizeMm);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Align(
          alignment: Alignment.center,
          child: SizedBox(
          width: qr,
          height: qr,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black26),
            ),
            child: Center(
              child: Icon(Icons.qr_code_2, size: qr * 0.85),
            ),
          ),
        ),
        ),
        SizedBox(height: 2 * scale / 6),
        Text(
          data.insertsLine,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 6 * scale / 6, height: 1.05),
        ),
        if (data.descriptionLine.isNotEmpty) ...[
          SizedBox(height: 1 * scale / 6),
          Text(
            data.descriptionLine,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 5.5 * scale / 6, height: 1.05),
          ),
        ],
      ],
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const dash = 3.0;
    final paint = Paint()
      ..color = Colors.red.withValues(alpha: 0.45)
      ..strokeWidth = 0.8;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0), Offset(x + dash, 0), paint);
      x += dash * 2;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}