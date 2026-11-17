import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/admin/admin_staff_session_store.dart';
import '../../../../core/services/database_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/models/seller_login_option.dart';
import '../pages/admin_web_shell.dart';

enum _StaffPanelLoginMode { seller, admin }

/// Пасхалка: вход продавца (PIN/пароль) или переключение в поток администратора.
///
/// Возвращает `true`, если выбран режим администратора (далее — стандартный PIN).
/// Возвращает `false`, если отмена. Продавец входит из диалога и уходит в [AdminWebShell].
Future<bool?> showStaffPanelLoginDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => const _StaffPanelLoginDialog(),
  );
}

class _StaffPanelLoginDialog extends StatefulWidget {
  const _StaffPanelLoginDialog();

  @override
  State<_StaffPanelLoginDialog> createState() => _StaffPanelLoginDialogState();
}

class _StaffPanelLoginDialogState extends State<_StaffPanelLoginDialog> {
  final DatabaseService _database = DatabaseService.create();
  _StaffPanelLoginMode _mode = _StaffPanelLoginMode.seller;

  List<SellerLoginOption> _sellers = const [];
  String? _selectedCode;
  bool _loadingSellers = true;
  bool _busy = false;
  String? _error;

  final _passwordController = TextEditingController();
  final _pinController = TextEditingController();
  final _pinFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _bootstrapSellers();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _pinController.dispose();
    _pinFocus.dispose();
    super.dispose();
  }

  SellerLoginOption? get _selected {
    final code = _selectedCode;
    if (code == null) return null;
    for (final row in _sellers) {
      if (row.promoCode == code) return row;
    }
    return null;
  }

  Future<void> _bootstrapSellers() async {
    try {
      final last = await AdminStaffSessionStore.readLastSelectedCode();
      final rows = await _database.getActiveSellersForLogin();
      if (!mounted) return;
      String? pick;
      if (last != null && rows.any((r) => r.promoCode == last)) {
        pick = last;
      } else if (rows.isNotEmpty) {
        pick = rows.first.promoCode;
      }
      setState(() {
        _sellers = rows;
        _selectedCode = pick;
        _loadingSellers = false;
      });
      if (_selected?.hasPin == true) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _pinFocus.requestFocus();
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingSellers = false;
        _error = 'Не удалось загрузить список продавцов';
      });
    }
  }

  void _onSellerChanged(String? code) {
    if (code == null) return;
    setState(() {
      _selectedCode = code;
      _error = null;
      _passwordController.clear();
      _pinController.clear();
    });
    unawaited(AdminStaffSessionStore.saveLastSelectedCode(code));
    if (_selected?.hasPin == true) {
      _pinFocus.requestFocus();
    }
  }

  void _onPinChanged(String value) {
    if (value.length == 4 && _selected?.hasPin == true) {
      _submitSellerLogin();
    }
  }

  Future<void> _submitSellerLogin() async {
    final selected = _selected;
    if (selected == null) {
      setState(() => _error = 'Выберите продавца');
      return;
    }

    final pin = _pinController.text.trim();
    final password = _passwordController.text;

    if (selected.hasPin) {
      if (pin.length != 4) {
        setState(() => _error = 'Введите PIN (4 цифры)');
        return;
      }
    } else {
      if (password.trim().isEmpty) {
        setState(() => _error = 'Введите пароль от администратора');
        return;
      }
      if (pin.length != 4) {
        setState(() => _error = 'Придумайте PIN из 4 цифр');
        return;
      }
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final result = await _database.sellerLoginOrSetupPin(
        promoCode: selected.promoCode,
        password: selected.hasPin ? null : password.trim(),
        pin: pin,
      );
      if (!mounted) return;
      if (result['ok'] != true) {
        setState(() {
          _busy = false;
          _error = result['error']?.toString() ?? 'Вход отклонён';
        });
        return;
      }

      final name = (result['name'] ?? selected.name).toString().trim();
      final code = (result['promo_code'] ?? selected.promoCode)
          .toString()
          .trim()
          .toUpperCase();

      await AdminStaffSessionStore.saveActiveSession(
        promoCode: code,
        name: name.isEmpty ? selected.name : name,
      );

      if (!mounted) return;
      final navigator = Navigator.of(context);
      navigator.pop(false);
      await navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const AdminWebShell(),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final message = error is StateError
          ? error.message
          : error.toString().replaceFirst('Exception: ', '');
      setState(() {
        _busy = false;
        _error = message;
      });
    }
  }

  void _continueAsAdmin() {
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        'Рабочая панель',
        style: AppTypography.heading(fontSize: 20),
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SegmentedButton<_StaffPanelLoginMode>(
              segments: const [
                ButtonSegment(
                  value: _StaffPanelLoginMode.seller,
                  label: Text('Продавец'),
                ),
                ButtonSegment(
                  value: _StaffPanelLoginMode.admin,
                  label: Text('Администратор'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: _busy
                  ? null
                  : (next) {
                      setState(() {
                        _mode = next.first;
                        _error = null;
                      });
                    },
            ),
            const SizedBox(height: 16),
            if (_mode == _StaffPanelLoginMode.admin)
              Text(
                'Далее откроется стандартная проверка PIN администратора.',
                style: AppTypography.productMeta().copyWith(fontSize: 13),
              )
            else ...[
              if (_loadingSellers)
                const Center(child: CircularProgressIndicator())
              else if (_sellers.isEmpty)
                Text(
                  'Нет активных продавцов',
                  style: AppTypography.productMeta(),
                )
              else ...[
                DropdownButtonFormField<String>(
                  initialValue: _selectedCode,
                  decoration: const InputDecoration(
                    labelText: 'Сотрудник',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final row in _sellers)
                      DropdownMenuItem(
                        value: row.promoCode,
                        child: Text('${row.name} · ${row.promoCode}'),
                      ),
                  ],
                  onChanged: _busy ? null : _onSellerChanged,
                ),
                const SizedBox(height: 12),
                if (_selected?.hasPin == true) ...[
                  TextField(
                    controller: _pinController,
                    focusNode: _pinFocus,
                    enabled: !_busy,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: _onPinChanged,
                    onSubmitted: (_) => _submitSellerLogin(),
                    decoration: const InputDecoration(
                      labelText: 'PIN-код (4 цифры)',
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ] else ...[
                  TextField(
                    controller: _passwordController,
                    enabled: !_busy,
                    obscureText: true,
                    textCapitalization: TextCapitalization.none,
                    onSubmitted: (_) => _pinFocus.requestFocus(),
                    decoration: const InputDecoration(
                      labelText: 'Пароль от админа',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _pinController,
                    focusNode: _pinFocus,
                    enabled: !_busy,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    maxLength: 4,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onSubmitted: (_) => _submitSellerLogin(),
                    decoration: const InputDecoration(
                      labelText: 'Придумайте PIN-код (4 цифры)',
                      counterText: '',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
            ],
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
          onPressed: _busy ? null : () => Navigator.of(context).pop(null),
          child: const Text('Отмена'),
        ),
        if (_mode == _StaffPanelLoginMode.admin)
          FilledButton(
            onPressed: _busy ? null : _continueAsAdmin,
            child: const Text('Продолжить'),
          )
        else
          FilledButton(
            onPressed: _busy || _loadingSellers || _sellers.isEmpty
                ? null
                : _submitSellerLogin,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Войти'),
          ),
      ],
    );
  }
}