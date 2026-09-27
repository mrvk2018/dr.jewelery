import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/services/device_secrets_store.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// Данные First Claim: учётные записи Supabase + локальный PIN.
class AdminFirstClaimCredentials {
  const AdminFirstClaimCredentials({
    required this.email,
    required this.password,
    required this.pin,
  });

  final String email;
  final String password;
  final String pin;
}

Future<AdminFirstClaimCredentials?> showAdminFirstClaimDialog(
  BuildContext context,
) async {
  return showDialog<AdminFirstClaimCredentials>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => const _AdminFirstClaimDialog(),
  );
}

class _AdminFirstClaimDialog extends StatefulWidget {
  const _AdminFirstClaimDialog();

  @override
  State<_AdminFirstClaimDialog> createState() => _AdminFirstClaimDialogState();
}

class _AdminFirstClaimDialogState extends State<_AdminFirstClaimDialog> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _pinController = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  void _submit() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final pin = _pinController.text.trim();

    if (email.isEmpty) {
      setState(() => _error = 'Введите email администратора');
      return;
    }
    if (password.isEmpty) {
      setState(() => _error = 'Введите пароль администратора');
      return;
    }
    if (!DeviceSecretsStore.isValidAdminPin(pin)) {
      setState(() => _error = 'PIN должен состоять из 4 цифр');
      return;
    }

    Navigator.of(context).pop(
      AdminFirstClaimCredentials(
        email: email,
        password: password,
        pin: pin,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Привязка администратора',
        style: AppTypography.heading(fontSize: 20),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Подтвердите учётную запись Supabase и задайте PIN '
              'для быстрого входа на этом устройстве.',
              style: AppTypography.productMeta().copyWith(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('admin_first_claim_email'),
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Email администратора',
                filled: true,
                fillColor: AppColors.cardBackground,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('admin_first_claim_password'),
              controller: _passwordController,
              obscureText: true,
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
            const SizedBox(height: 12),
            TextField(
              key: const Key('admin_first_claim_pin'),
              controller: _pinController,
              obscureText: true,
              keyboardType: TextInputType.number,
              maxLength: 4,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Новый PIN (4 цифры)',
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
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          key: const Key('admin_first_claim_submit'),
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.textOnPrimary,
          ),
          child: const Text('Подтвердить'),
        ),
      ],
    );
  }
}
