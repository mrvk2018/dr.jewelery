import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/services/device_secrets_store.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/providers/profile_scope.dart';

/// Локальная проверка PIN (без сети). [forPanelAccess] — только сверка PIN, без signInAdmin.
Future<bool> showAdminPinUnlockDialog(
  BuildContext context, {
  bool forPanelAccess = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _AdminPinUnlockDialog(forPanelAccess: forPanelAccess),
  );
  return ok ?? false;
}

class _AdminPinUnlockDialog extends StatefulWidget {
  const _AdminPinUnlockDialog({required this.forPanelAccess});

  final bool forPanelAccess;

  @override
  State<_AdminPinUnlockDialog> createState() => _AdminPinUnlockDialogState();
}

class _AdminPinUnlockDialogState extends State<_AdminPinUnlockDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _controller.text.trim();
    if (!DeviceSecretsStore.isValidAdminPin(pin)) {
      setState(() => _error = 'Введите 4-значный PIN');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final profile = ProfileScope.of(context);
    final unlocked = widget.forPanelAccess
        ? await profile.verifyAdminPinForPanel(pin)
        : await profile.unlockAdminWithPin(pin);

    if (!mounted) return;
    if (unlocked) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _busy = false;
      _error = 'Неверный PIN. Доступ запрещён.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        widget.forPanelAccess ? 'Доступ к панели' : 'Вход администратора',
        style: AppTypography.heading(fontSize: 20),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.forPanelAccess
                ? 'Введите PIN администратора для открытия панели управления.'
                : 'Введите PIN администратора, заданный при первой привязке.',
            style: AppTypography.productMeta().copyWith(fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('admin_unlock_pin'),
            controller: _controller,
            obscureText: true,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            maxLength: 4,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'PIN (4 цифры)',
              counterText: '',
              filled: true,
              fillColor: AppColors.cardBackground,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: AppTypography.caption(color: AppColors.saleRed)
                  .copyWith(fontSize: 13),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          key: const Key('admin_unlock_submit'),
          onPressed: _busy ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.textOnPrimary,
          ),
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Продолжить'),
        ),
      ],
    );
  }
}
