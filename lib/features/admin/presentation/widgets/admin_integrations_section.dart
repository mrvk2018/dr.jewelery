import 'package:flutter/material.dart';

import '../../../../core/services/device_secrets_store.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/providers/profile_scope.dart';

/// Локальные API-ключи кассы и Toss Payments.
class AdminIntegrationsSection extends StatefulWidget {
  const AdminIntegrationsSection({super.key});

  @override
  State<AdminIntegrationsSection> createState() =>
      _AdminIntegrationsSectionState();
}

class _AdminIntegrationsSectionState extends State<AdminIntegrationsSection> {
  final _posController = TextEditingController();
  final _tossController = TextEditingController();
  bool _ready = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final keys = await ProfileScope.of(context).loadIntegrationKeys();
    if (!mounted) return;
    _posController.text = keys.posApiKey;
    _tossController.text = keys.tossApiKey;
    setState(() => _ready = true);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    await ProfileScope.of(context).saveIntegrationKeys(
      IntegrationKeys(
        posApiKey: _posController.text,
        tossApiKey: _tossController.text,
      ),
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Ключи сохранены на этом устройстве',
          style: AppTypography.caption(
            color: AppColors.textOnPrimary,
            fontWeight: FontWeight.w600,
          ).copyWith(fontSize: 14),
        ),
        backgroundColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  void dispose() {
    _posController.dispose();
    _tossController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Интеграции',
          style: AppTypography.heading(fontSize: 20),
        ),
        const SizedBox(height: 8),
        Text(
          'Тестовые и боевые ключи кассы и Toss Payments. '
          'Нужны для синхронизации остатков и приёма оплаты.',
          style: AppTypography.productMeta().copyWith(fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 20),
        _MaskedKeyField(
          key: const Key('admin_pos_api_key'),
          controller: _posController,
          label: 'API Ключ Кассовой системы (POS API Key)',
          enabled: _ready && !_saving,
        ),
        const SizedBox(height: 16),
        _MaskedKeyField(
          key: const Key('admin_toss_api_key'),
          controller: _tossController,
          label: 'API Ключ платежей (Toss Payments Key)',
          enabled: _ready && !_saving,
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 48,
          child: ElevatedButton(
            key: const Key('admin_save_keys'),
            onPressed: _ready && !_saving ? _save : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textOnPrimary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(_saving ? 'Сохранение...' : 'Сохранить ключи'),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          '🔒 Ключи хранятся локально на вашем устройстве и не передаются третьим лицам',
          style: AppTypography.productMeta().copyWith(fontSize: 12, height: 1.4),
        ),
      ],
    );
  }
}

class _MaskedKeyField extends StatelessWidget {
  const _MaskedKeyField({
    super.key,
    required this.controller,
    required this.label,
    required this.enabled,
  });

  final TextEditingController controller;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: true,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColors.cardBackground,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
      ),
    );
  }
}
