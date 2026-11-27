import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';

/// Потоковый QR-сканер: камера (mobile_scanner) + HID-клавиатура (USB/BT 2D).
class UniversalQrScannerSheet extends StatefulWidget {
  const UniversalQrScannerSheet({
    super.key,
    required this.onScan,
    this.title = 'Сканирование',
    this.footer,
    this.cooldown = const Duration(seconds: 3),
  });

  final Future<void> Function(String payload) onScan;
  final String title;
  final Widget? footer;
  final Duration cooldown;

  static Future<void> show(
    BuildContext context, {
    required String title,
    required Future<void> Function(String payload) onScan,
    Widget? footer,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.cardBackground,
      builder: (ctx) => UniversalQrScannerSheet(
        title: title,
        onScan: onScan,
        footer: footer,
      ),
    );
  }

  @override
  State<UniversalQrScannerSheet> createState() =>
      _UniversalQrScannerSheetState();
}

class _UniversalQrScannerSheetState extends State<UniversalQrScannerSheet> {
  final MobileScannerController _camera = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  final FocusNode _hidFocus = FocusNode();
  String _hidBuffer = '';
  String? _lastPayload;
  DateTime? _lastAt;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _hidFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _camera.dispose();
    _hidFocus.dispose();
    super.dispose();
  }

  bool _shouldSkip(String payload) {
    final now = DateTime.now();
    if (_lastPayload == payload &&
        _lastAt != null &&
        now.difference(_lastAt!) < widget.cooldown) {
      return true;
    }
    _lastPayload = payload;
    _lastAt = now;
    return false;
  }

  Future<void> _dispatch(String payload) async {
    final text = payload.trim();
    if (text.isEmpty || _busy) return;
    if (_shouldSkip(text)) return;
    setState(() => _busy = true);
    unawaited(SystemSound.play(SystemSoundType.click));
    unawaited(HapticFeedback.mediumImpact());
    try {
      await widget.onScan(text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onDetect(BarcodeCapture capture) {
    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;
    final raw = barcodes.first.rawValue;
    if (raw == null || raw.trim().isEmpty) return;
    unawaited(_dispatch(raw));
  }

  KeyEventResult _onHidKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final label = event.logicalKey.keyLabel;
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final line = _hidBuffer.trim();
      _hidBuffer = '';
      if (line.isNotEmpty) {
        unawaited(_dispatch(line));
      }
      return KeyEventResult.handled;
    }
    if (label.length == 1 && label != 'Shift' && label != 'Shift Left' && label != 'Shift Right') {
      _hidBuffer += label;
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final viewHeight = MediaQuery.sizeOf(context).height;
    final cameraHeight = (viewHeight * 0.42).clamp(220.0, 420.0);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: AppTypography.heading(fontSize: 18),
                ),
              ),
              IconButton(
                tooltip: 'Закрыть',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Камера активна; повтор того же QR — не чаще ${widget.cooldown.inSeconds} с. '
            'USB/BT-сканер: фокус в поле ниже.',
            style: AppTypography.productMeta(),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: cameraHeight,
              child: ColoredBox(
                color: Colors.black,
                child: MobileScanner(
                  controller: _camera,
                  onDetect: _onDetect,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Focus(
            focusNode: _hidFocus,
            onKeyEvent: _onHidKey,
            child: TextField(
              readOnly: true,
              showCursor: false,
              decoration: InputDecoration(
                hintText: 'Физический сканер (Enter завершает строку)',
                suffixIcon: _busy
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Icon(Icons.usb_outlined),
              ),
            ),
          ),
        ),
        if (widget.footer != null) ...[
          const Divider(height: 1),
          widget.footer!,
        ],
        SizedBox(height: MediaQuery.paddingOf(context).bottom + 8),
      ],
    );
  }
}