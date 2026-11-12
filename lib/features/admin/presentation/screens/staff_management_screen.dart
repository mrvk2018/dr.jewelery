import 'package:flutter/material.dart';

import '../../../../core/services/database_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../profile/domain/models/user_profile.dart';
import '../../../../shared/models/seller_item.dart';

/// Картотека продавцов (Incheon super-admin): чтение + RPC upsert.
class StaffManagementScreen extends StatefulWidget {
  StaffManagementScreen({super.key, DatabaseService? database})
      : database = database ?? DatabaseService.create();

  final DatabaseService database;

  @override
  State<StaffManagementScreen> createState() => _StaffManagementScreenState();
}

class _StaffManagementScreenState extends State<StaffManagementScreen> {
  List<SellerItem> _sellers = const [];
  bool _loading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final list = await widget.database.getSellers(UserRole.admin);
      if (!mounted) return;
      setState(() {
        _sellers = list;
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

  Future<void> _openUpsertDialog({SellerItem? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _StaffUpsertDialog(
        database: widget.database,
        existing: existing,
      ),
    );
    if (saved == true && mounted) await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Управление персоналом',
                  style: AppTypography.heading(fontSize: 22),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: _loading ? null : () => _openUpsertDialog(),
                  icon: const Icon(Icons.person_add_outlined),
                  label: const Text('Добавить сотрудника'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Код сотрудника (6 символов) — поле promo_code в sellers; '
              'используется в POS и реферальной системе.',
              style: AppTypography.productMeta(),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _loadError != null
                      ? Center(
                          child: Text(
                            'Ошибка загрузки: $_loadError',
                            style: AppTypography.productMeta(),
                          ),
                        )
                      : _sellers.isEmpty
                          ? Center(
                              child: Text(
                                'Нет записей. Добавьте первого сотрудника.',
                                style: AppTypography.productMeta(),
                              ),
                            )
                          : Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(color: AppColors.border),
                              ),
                              child: ListView.separated(
                                itemCount: _sellers.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final seller = _sellers[index];
                                  return ListTile(
                                    title: Text(seller.name),
                                    subtitle: Text(
                                      seller.promoCode,
                                      style: AppTypography.productMeta(),
                                    ),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Chip(
                                          label: Text(
                                            seller.isActive
                                                ? 'Активен'
                                                : 'Отключён',
                                            style: const TextStyle(fontSize: 11),
                                          ),
                                          backgroundColor: seller.isActive
                                              ? Colors.green.withValues(
                                                  alpha: 0.12,
                                                )
                                              : AppColors.saleRed.withValues(
                                                  alpha: 0.12,
                                                ),
                                        ),
                                        IconButton(
                                          tooltip: 'Редактировать',
                                          onPressed: () =>
                                              _openUpsertDialog(existing: seller),
                                          icon: const Icon(Icons.edit_outlined),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StaffUpsertDialog extends StatefulWidget {
  const _StaffUpsertDialog({
    required this.database,
    this.existing,
  });

  final DatabaseService database;
  final SellerItem? existing;

  bool get isEdit => existing != null;

  @override
  State<_StaffUpsertDialog> createState() => _StaffUpsertDialogState();
}

class _StaffUpsertDialogState extends State<_StaffUpsertDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _codeController;
  late bool _isActive;
  bool _saving = false;
  String? _error;

  static final _codePattern = RegExp(r'^[A-Z0-9]{6}$');

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _codeController =
        TextEditingController(text: existing?.promoCode ?? '');
    _isActive = existing?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final code =
        SellerItem.normalizePromoCode(_codeController.text);
    if (name.isEmpty) {
      setState(() => _error = 'Укажите имя');
      return;
    }
    if (!_codePattern.hasMatch(code)) {
      setState(
        () => _error = 'Код: ровно 6 латинских букв или цифр (A–Z, 0–9)',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.database.upsertSellerByAdmin(
        promoCode: code,
        name: name,
        isActive: _isActive,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      final message = error is StateError
          ? error.message
          : error.toString().replaceFirst('Exception: ', '');
      setState(() {
        _saving = false;
        _error = message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.isEdit ? 'Редактировать сотрудника' : 'Добавить сотрудника',
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Имя',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _codeController,
              enabled: !widget.isEdit,
              decoration: const InputDecoration(
                labelText: 'Код сотрудника (6 символов)',
                border: OutlineInputBorder(),
                helperText: 'Например: AEU256',
              ),
              textCapitalization: TextCapitalization.characters,
              maxLength: 6,
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Активен'),
              value: _isActive,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _isActive = value),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: AppTypography.productMeta().copyWith(
                  color: AppColors.saleRed,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Сохранить'),
        ),
      ],
    );
  }
}
