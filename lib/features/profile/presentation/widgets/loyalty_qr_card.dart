import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// Визуальный плейсхолдер QR-кода карты лояльности.
class LoyaltyQrCard extends StatelessWidget {
  const LoyaltyQrCard({
    super.key,
    required this.cardNumber,
    required this.ownerName,
  });

  final String cardNumber;
  final String ownerName;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Карта лояльности',
            style: AppTypography.heading(fontSize: 18),
          ),
          const SizedBox(height: 4),
          Text(
            ownerName,
            style: AppTypography.productMeta().copyWith(fontSize: 13),
          ),
          const SizedBox(height: 16),
          Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: const _QrPlaceholder(size: 140),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              cardNumber,
              style: AppTypography.caption(fontWeight: FontWeight.w600)
                  .copyWith(fontSize: 13, letterSpacing: 1.2),
            ),
          ),
        ],
      ),
    );
  }
}

class _QrPlaceholder extends StatelessWidget {
  const _QrPlaceholder({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _QrPatternPainter(),
    );
  }
}

class _QrPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 11;
    final paint = Paint()..color = AppColors.primary;

    for (var row = 0; row < 11; row++) {
      for (var col = 0; col < 11; col++) {
        final draw = (row + col) % 3 != 0 && (row * col) % 5 != 0;
        if (draw) {
          canvas.drawRect(
            Rect.fromLTWH(col * cell, row * cell, cell * 0.82, cell * 0.82),
            paint,
          );
        }
      }
    }

    final corner = Paint()..color = AppColors.primary;
    canvas.drawRect(Rect.fromLTWH(0, 0, cell * 3, cell * 3), corner);
    canvas.drawRect(
      Rect.fromLTWH(size.width - cell * 3, 0, cell * 3, cell * 3),
      corner,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, size.height - cell * 3, cell * 3, cell * 3),
      corner,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
