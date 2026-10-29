import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/theme/app_colors.dart';

/// Постоянно активная камера для считывания `qr_code_payload`.
class SellerQrScanner extends StatefulWidget {
  const SellerQrScanner({
    super.key,
    required this.onDetected,
  });

  final ValueChanged<String> onDetected;

  @override
  State<SellerQrScanner> createState() => _SellerQrScannerMobileState();
}

class _SellerQrScannerMobileState extends State<SellerQrScanner> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  String? _lastPayload;
  DateTime? _lastAt;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final raw = barcodes.first.rawValue?.trim();
    if (raw == null || raw.isEmpty) return;

    final now = DateTime.now();
    if (_lastPayload == raw &&
        _lastAt != null &&
        now.difference(_lastAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastPayload = raw;
    _lastAt = now;
    widget.onDetected(raw);
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.border),
        ),
        child: AspectRatio(
          aspectRatio: 3 / 4,
          child: MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
        ),
      ),
    );
  }
}
