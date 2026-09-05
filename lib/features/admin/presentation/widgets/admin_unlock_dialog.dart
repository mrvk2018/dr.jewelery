import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/providers/profile_scope.dart';

/// Запрос пароля владельца после First Claim.
Future<bool> showAdminUnlockDialog(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => const _AdminUnlockDialog(),
  );
  return ok ?? false;
}

class _AdminUnlockDialog extends StatefulWidget {
  const _AdminUnlockDialog();

  @override
  State<_AdminUnlockDialog> createState() => _AdminUnlockDialogState();
}

class _AdminUnlockDialogState extends State<_AdminUnlockDialog> {
  final _controller = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _controller.text;
    if (password.trim().isEmpty) {
      setState(() => _error = 'Введите пароль');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    final unlocked = await ProfileScope.of(context).unlockAdmin(password);
    if (!mounted) return;
    if (unlocked) {
      Navigator.of(context).pop(true);
      return;
    }

    setState(() {
      _busy = false;
      _error = 'Неверный пароль. Доступ в админку запрещён.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Вход владельца',
        style: AppTypography.heading(fontSize: 20),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Устройство уже закреплено за владельцем. '
            'Введите пароль администратора.',
            style: AppTypography.productMeta().copyWith(fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('admin_unlock_password'),
            controller: _controller,
            obscureText: true,
            enabled: !_busy,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Пароль администратора',
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
              : const Text('Войти'),
        ),
      ],
    );
  }
}
