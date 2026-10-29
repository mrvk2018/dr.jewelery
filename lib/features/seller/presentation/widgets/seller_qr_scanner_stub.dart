import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Web / desktop fallback: ручной ввод QR (APK использует [SellerQrScanner] mobile).
class SellerQrScanner extends StatefulWidget {
  const SellerQrScanner({
    super.key,
    required this.onDetected,
  });

  final ValueChanged<String> onDetected;

  @override
  State<SellerQrScanner> createState() => _SellerQrScannerStubState();
}

class _SellerQrScannerStubState extends State<SellerQrScanner> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    if (value.isEmpty) return;
    widget.onDetected(value);
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('QR (ручной ввод / эмулятор)'),
            const SizedBox(height: 8),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'qr_code_payload',
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 8),
            FilledButton(onPressed: _submit, child: const Text('Сканировать')),
          ],
        ),
      ),
    );
  }
}
