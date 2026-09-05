import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// Полноэкранная инициализация владельца (First Claim).
class AdminOwnerInitPage extends StatefulWidget {
  const AdminOwnerInitPage({super.key});

  @override
  State<AdminOwnerInitPage> createState() => _AdminOwnerInitPageState();
}

class _AdminOwnerInitPageState extends State<AdminOwnerInitPage> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _error;
  bool _obscure = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _passwordController.text;
    final confirm = _confirmController.text;
    if (password.trim().isEmpty) {
      setState(() => _error = 'Введите пароль администратора');
      return;
    }
    if (password != confirm) {
      setState(() => _error = 'Пароли не совпадают');
      return;
    }
    Navigator.of(context).pop(password);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.accent,
        elevation: 0,
        title: Text(
          'Dr. Jewelry',
          style: AppTypography.heading(fontSize: 18, color: AppColors.accent),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.accent, width: 1.5),
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  color: AppColors.accent,
                  size: 34,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Инициализация владельца Dr. Jewelry',
                style: AppTypography.heading(
                  fontSize: 26,
                  color: AppColors.textOnPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Придумайте сложный пароль администратора. '
                'Это полноценная текстовая строка, не PIN-код. '
                'После сохранения устройство будет закреплено за вами навсегда.',
                style: AppTypography.productMeta().copyWith(
                  fontSize: 14,
                  height: 1.5,
                  color: AppColors.navInactive,
                ),
              ),
              const SizedBox(height: 32),
              _PasswordField(
                key: const Key('admin_claim_password'),
                controller: _passwordController,
                label: 'Пароль администратора',
                obscure: _obscure,
                onToggleObscure: () => setState(() => _obscure = !_obscure),
              ),
              const SizedBox(height: 16),
              _PasswordField(
                key: const Key('admin_claim_confirm'),
                controller: _confirmController,
                label: 'Повторите пароль',
                obscure: _obscure,
                onToggleObscure: () => setState(() => _obscure = !_obscure),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: AppTypography.caption(color: AppColors.saleRed)
                      .copyWith(fontSize: 13),
                ),
              ],
              const SizedBox(height: 28),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  key: const Key('admin_claim_submit'),
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: AppColors.textOnAccent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Назначить владельца',
                    style: AppTypography.caption(
                      color: AppColors.textOnAccent,
                      fontWeight: FontWeight.w700,
                    ).copyWith(fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    super.key,
    required this.controller,
    required this.label,
    required this.obscure,
    required this.onToggleObscure,
  });

  final TextEditingController controller;
  final String label;
  final bool obscure;
  final VoidCallback onToggleObscure;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: AppTypography.caption(color: AppColors.textOnPrimary)
          .copyWith(fontSize: 15),
      cursorColor: AppColors.accent,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: AppTypography.productMeta().copyWith(
          color: AppColors.navInactive,
        ),
        filled: true,
        fillColor: const Color(0xFF1C1C1C),
        suffixIcon: IconButton(
          onPressed: onToggleObscure,
          icon: Icon(
            obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            color: AppColors.accent,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF333333)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
      ),
    );
  }
}
