import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/jewelry_label_data.dart';
import '../../domain/jewelry_label_layout.dart';

/// Превью гантельки 60×12 mm (лицо слева · перемычка · оборот справа).
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
          'Гантелька · 60×12 mm (лицо слева)',
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
                  left: mmPx(JewelryLabelLayout.leftCutLineMm),
                  top: 0,
                  bottom: 0,
                  child: _verticalCutGuide(),
                ),
                Positioned(
                  left: mmPx(JewelryLabelLayout.rightCutLineMm),
                  top: 0,
                  bottom: 0,
                  child: _verticalCutGuide(),
                ),
                Positioned(
                  left: mmPx(JewelryLabelLayout.bridgeLeftMm),
                  top: 0,
                  width: mmPx(
                    JewelryLabelLayout.bridgeRightMm -
                        JewelryLabelLayout.bridgeLeftMm,
                  ),
                  height: height,
                  child: ColoredBox(color: Colors.grey.shade100),
                ),
              ],
              ..._frontEarLayers(data, scale, mmPx),
              ..._backEarLayers(data, scale, mmPx),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _frontEarLayers(
    JewelryLabelData data,
    double scale,
    double Function(double mm) mmPx,
  ) {
    final layers = <Widget>[];

    Text line(
      String text, {
      required double fontPt,
      FontWeight weight = FontWeight.w400,
    }) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: TextStyle(
          fontSize: fontPt * scale / 6,
          height: 1.05,
          fontWeight: weight,
          color: AppColors.textPrimary,
        ),
      );
    }

    void add(double yMm, Widget child) {
      layers.add(
        Positioned(
          left: mmPx(JewelryLabelLayout.frontContentLeftMm),
          top: mmPx(yMm),
          width: mmPx(JewelryLabelLayout.frontContentWidthMm),
          child: child,
        ),
      );
    }

    add(
      JewelryLabelLayout.frontCategoryYmm,
      line(
        data.category,
        fontPt: JewelryLabelLayout.fontCategoryPt,
        weight: FontWeight.w700,
      ),
    );
    if (data.subtype.isNotEmpty) {
      add(
        JewelryLabelLayout.frontSubtypeYmm,
        line(data.subtype, fontPt: JewelryLabelLayout.fontSubtypePt),
      );
    }
    add(
      JewelryLabelLayout.frontWeightYmm,
      line(
        data.weightLine,
        fontPt: JewelryLabelLayout.fontWeightPt,
        weight: FontWeight.w700,
      ),
    );
    if (data.sizeLine.isNotEmpty) {
      add(
        JewelryLabelLayout.frontSizeYmm,
        line(data.sizeLine, fontPt: JewelryLabelLayout.fontSizePt),
      );
    }
    add(
      JewelryLabelLayout.frontPriceYmm,
      line(
        data.showroomPriceLine,
        fontPt: JewelryLabelLayout.fontPricePt,
        weight: FontWeight.w800,
      ),
    );

    return layers;
  }

  List<Widget> _backEarLayers(
    JewelryLabelData data,
    double scale,
    double Function(double mm) mmPx,
  ) {
    final qrSide = mmPx(JewelryLabelLayout.backQrSizeMm);
    final backDesc = data.backDescriptionLine;
    final backTextY = JewelryLabelLayout.backTextYMm(
      hasSize: data.hasBackSize,
      hasDescription: backDesc.isNotEmpty,
    );

    Text backText(
      String text, {
      required double fontPt,
      int maxLines = 1,
    }) {
      return Text(
        text,
        maxLines: maxLines,
        overflow: TextOverflow.clip,
        style: TextStyle(
          fontSize: fontPt * scale / 6,
          height: 1.05,
          color: AppColors.textPrimary,
        ),
      );
    }

    final layers = <Widget>[
      Positioned(
        left: mmPx(JewelryLabelLayout.backQrLeftMm),
        top: mmPx(JewelryLabelLayout.backQrTopMm),
        width: qrSide,
        height: qrSide,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black26),
          ),
          child: Center(
            child: Icon(Icons.qr_code_2, size: qrSide * 0.85),
          ),
        ),
      ),
    ];

    void addTextRow(double yMm, Widget child) {
      layers.add(
        Positioned(
          left: mmPx(JewelryLabelLayout.backTextLeftMm),
          top: mmPx(yMm),
          width: mmPx(JewelryLabelLayout.backTextWidthMm),
          child: child,
        ),
      );
    }

    if (data.hasBackSize) {
      addTextRow(
        backTextY.sizeY!,
        backText(data.backSizeLine, fontPt: JewelryLabelLayout.fontSizePt),
      );
    }

    addTextRow(
      backTextY.insertsY,
      backText(data.insertsLine, fontPt: JewelryLabelLayout.fontInsertsPt),
    );

    if (backDesc.isNotEmpty && backTextY.descriptionY != null) {
      addTextRow(
        backTextY.descriptionY!,
        backText(
          backDesc,
          fontPt: JewelryLabelLayout.fontDescriptionPt,
          maxLines: JewelryLabelLayout.backDescriptionMaxLines,
        ),
      );
    }

    return layers;
  }

  Widget _verticalCutGuide() => LayoutBuilder(
        builder: (context, constraints) {
          return CustomPaint(
            size: Size(1, constraints.maxHeight),
            painter: _DashedLinePainter(axis: Axis.vertical),
          );
        },
      );
}

class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter({this.axis = Axis.horizontal});

  final Axis axis;

  @override
  void paint(Canvas canvas, Size size) {
    const dash = 3.0;
    final paint = Paint()
      ..color = Colors.red.withValues(alpha: 0.45)
      ..strokeWidth = 0.8;

    if (axis == Axis.horizontal) {
      var x = 0.0;
      while (x < size.width) {
        canvas.drawLine(Offset(x, 0), Offset(x + dash, 0), paint);
        x += dash * 2;
      }
      return;
    }

    var y = 0.0;
    while (y < size.height) {
      canvas.drawLine(Offset(0, y), Offset(0, y + dash), paint);
      y += dash * 2;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) =>
      oldDelegate.axis != axis;
}