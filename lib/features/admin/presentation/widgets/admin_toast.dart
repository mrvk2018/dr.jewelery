import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

const _adminToastWideBreakpoint = 900.0;

OverlayEntry? _adminToastEntry;

void showAdminToast(
  BuildContext context,
  String message, {
  bool error = false,
}) {
  final text = message.trim();
  if (text.isEmpty) return;

  final wide = MediaQuery.sizeOf(context).width >= _adminToastWideBreakpoint;
  if (!wide) {
    _removeAdminToast();
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text, maxLines: 3, overflow: TextOverflow.ellipsis),
          behavior: SnackBarBehavior.floating,
          backgroundColor: error ? AppColors.saleRed : const Color(0xFF1C1C1C),
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 72),
          duration: const Duration(milliseconds: 2700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
          ),
        ),
      );
    return;
  }

  final host = Overlay.maybeOf(context, rootOverlay: true);
  if (host == null) return;
  ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
  _removeAdminToast();

  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _AdminRailToast(
      message: text,
      error: error,
      onDismiss: () {
        if (_adminToastEntry == entry) _removeAdminToast();
      },
    ),
  );
  _adminToastEntry = entry;
  host.insert(entry);
}

void _removeAdminToast() {
  _adminToastEntry?.remove();
  _adminToastEntry = null;
}

class _AdminRailToast extends StatefulWidget {
  const _AdminRailToast({
    required this.message,
    required this.error,
    required this.onDismiss,
  });

  final String message;
  final bool error;
  final VoidCallback onDismiss;

  @override
  State<_AdminRailToast> createState() => _AdminRailToastState();
}

class _AdminRailToastState extends State<_AdminRailToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      reverseDuration: const Duration(milliseconds: 160),
    )..forward();
    _timer = Timer(const Duration(milliseconds: 2700), _close);
  }

  Future<void> _close() async {
    _timer?.cancel();
    if (!mounted) return;
    await _fade.reverse();
    if (mounted) widget.onDismiss();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final border = widget.error
        ? AppColors.saleRed
        : Colors.white.withValues(alpha: 0.28);
    final icon = widget.error
        ? Icons.error_outline
        : Icons.check_circle_outline;
    return Positioned(
      left: 12,
      bottom: 16,
      width: 168,
      child: FadeTransition(
        opacity: _fade,
        child: GestureDetector(
          onTap: _close,
          child: Material(
            color: const Color(0xFF1C1C1C),
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              constraints: const BoxConstraints(minHeight: 112),
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: border),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 18, color: border),
                  const SizedBox(height: 8),
                  Text(
                    widget.message,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.productMeta().copyWith(
                      color: AppColors.textOnPrimary,
                      height: 1.25,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
