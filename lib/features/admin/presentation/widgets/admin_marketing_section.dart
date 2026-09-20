import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/services/database_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../features/profile/domain/models/user_profile.dart';
import '../../../../shared/models/app_marketing_settings.dart';

/// Welcome-акция (Facebook / Instagram) — `public.app_settings`.
class AdminMarketingSection extends StatefulWidget {
  const AdminMarketingSection({super.key, required this.database});

  final DatabaseService database;

  @override
  State<AdminMarketingSection> createState() => _AdminMarketingSectionState();
}

class _AdminMarketingSectionState extends State<AdminMarketingSection> {
  bool _loading = true;
  bool _saving = false;
  bool _enabled = false;
  final _amountController = TextEditingController(text: '0');
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final settings = await widget.database.getAppMarketingSettings();
      if (!mounted) return;
      setState(() {
        _enabled = settings.welcomeBonusEnabled;
        _amountController.text = settings.welcomeBonusAmountKrw.toString();
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error.toString();
      });
    }
  }

  Future<void> _save() async {
    final amount = int.tryParse(_amountController.text.trim()) ?? 0;
    setState(() => _saving = true);
    try {
      await widget.database.saveAppMarketingSettings(
        AppMarketingSettings(
          welcomeBonusEnabled: _enabled,
          welcomeBonusAmountKrw: amount < 0 ? 0 : amount,
        ),
        UserRole.admin,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Настройки маркетинга сохранены',
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
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка: $error'),
          backgroundColor: AppColors.saleRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Text('Управление маркетингом', style: AppTypography.heading(fontSize: 20)),
          const SizedBox(height: 8),
          Text(
            'Приветственный бонус начисляется новым пользователям Supabase Auth '
            'при регистрации, если акция включена (таблица app_settings).',
            style: AppTypography.productMeta().copyWith(fontSize: 13, height: 1.4),
          ),
          if (_loadError != null) ...[
            const SizedBox(height: 12),
            Text(
              _loadError!,
              style: AppTypography.productMeta().copyWith(color: AppColors.saleRed),
            ),
          ],
          const SizedBox(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Приветственная акция активна',
              style: AppTypography.caption(fontWeight: FontWeight.w600)
                  .copyWith(fontSize: 15),
            ),
            subtitle: Text(
              'Facebook / Instagram — бонус при первой регистрации',
              style: AppTypography.productMeta().copyWith(fontSize: 12),
            ),
            value: _enabled,
            activeThumbColor: AppColors.accent,
            onChanged: _saving ? null : (value) => setState(() => _enabled = value),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amountController,
            enabled: !_saving,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: 'Сумма бонуса (KRW)',
              filled: true,
              fillColor: AppColors.cardBackground,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textOnPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(_saving ? 'Сохранение...' : 'Сохранить'),
            ),
          ),
        ],
      ),
    );
  }
}
