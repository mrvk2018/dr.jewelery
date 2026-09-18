import 'package:flutter/material.dart';

import '../../../../core/services/database_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../features/profile/domain/models/user_profile.dart';
import '../../../../shared/models/seller_item.dart';

/// Картотека продавцов: промокоды и имена (чтение и запись через [DatabaseService]).
class AdminSellersSection extends StatefulWidget {
  const AdminSellersSection({super.key, required this.database});

  final DatabaseService database;

  @override
  State<AdminSellersSection> createState() => _AdminSellersSectionState();
}

class _AdminSellersSectionState extends State<AdminSellersSection> {
  final _promoController = TextEditingController();
  final _nameController = TextEditingController();

  List<SellerItem> _sellers = [];
  bool _loading = true;
  bool _saving = false;
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

  void _showSnack(String text, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          text,
          style: AppTypography.caption(
            color: AppColors.textOnPrimary,
            fontWeight: FontWeight.w600,
          ).copyWith(fontSize: 14),
        ),
        backgroundColor: isError ? AppColors.saleRed : AppColors.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  Future<void> _saveSeller() async {
    final promo = SellerItem.normalizePromoCode(_promoController.text);
    final name = _nameController.text.trim();
    if (promo.isEmpty || name.isEmpty) {
      _showSnack('Укажите промокод и имя продавца', isError: true);
      return;
    }
    if (promo.length > 50 || name.length > 255) {
      _showSnack('Слишком длинное значение (код ≤ 50, имя ≤ 255)', isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final item = SellerItem(promoCode: promo, name: name);
      await widget.database.saveSeller(item, UserRole.admin);
      _promoController.clear();
      _nameController.clear();
      await _reload();
      if (!mounted) return;
      _showSnack('Продавец сохранён');
    } catch (error) {
      if (!mounted) return;
      _showSnack('Не удалось сохранить: $error', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setActive(SellerItem seller, bool active) async {
    try {
      await widget.database.saveSeller(
        seller.copyWith(isActive: active),
        UserRole.admin,
      );
      await _reload();
    } catch (error) {
      if (!mounted) return;
      _showSnack('Не удалось обновить статус: $error', isError: true);
    }
  }

  Future<void> _deleteSeller(String promoCode) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Удалить продавца?', style: AppTypography.heading(fontSize: 18)),
        content: Text(
          'Промокод $promoCode будет удалён из картотеки.',
          style: AppTypography.productMeta(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.saleRed),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await widget.database.deleteSeller(promoCode, UserRole.admin);
      await _reload();
      if (!mounted) return;
      _showSnack('Продавец удалён');
    } catch (error) {
      if (!mounted) return;
      _showSnack('Не удалось удалить: $error', isError: true);
    }
  }

  @override
  void dispose() {
    _promoController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.all(16),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Text('Продавцы и промокоды', style: AppTypography.heading(fontSize: 20)),
          const SizedBox(height: 8),
          Text(
            'Картотека для реферальной системы: имя и код попадают в Supabase '
            '(таблица sellers). Ключи API в приложении не хранятся.',
            style: AppTypography.productMeta().copyWith(fontSize: 13, height: 1.4),
          ),
          if (_loadError != null) ...[
            const SizedBox(height: 12),
            Text(
              _loadError!,
              style: AppTypography.productMeta().copyWith(color: AppColors.saleRed),
            ),
          ],
          const SizedBox(height: 20),
          TextField(
            controller: _promoController,
            enabled: !_saving,
            textCapitalization: TextCapitalization.characters,
            decoration: _fieldDecoration('Промокод'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            enabled: !_saving,
            decoration: _fieldDecoration('Имя продавца / блогера'),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _saving ? null : _saveSeller,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textOnPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(_saving ? 'Сохранение...' : 'Добавить / обновить'),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'Записи (${_sellers.length})',
            style: AppTypography.heading(fontSize: 18),
          ),
          const SizedBox(height: 12),
          if (_sellers.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'Пока нет продавцов — добавьте первую запись выше.',
                style: AppTypography.productMeta(),
              ),
            )
          else
            ..._sellers.map((seller) => _SellerRow(
                  seller: seller,
                  onToggleActive: (value) => _setActive(seller, value),
                  onDelete: () => _deleteSeller(seller.promoCode),
                )),
        ],
      ),
    );
  }

  InputDecoration _fieldDecoration(String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: AppColors.cardBackground,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
    );
  }
}

class _SellerRow extends StatelessWidget {
  const _SellerRow({
    required this.seller,
    required this.onToggleActive,
    required this.onDelete,
  });

  final SellerItem seller;
  final ValueChanged<bool> onToggleActive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    seller.promoCode,
                    style: AppTypography.caption(fontWeight: FontWeight.w800)
                        .copyWith(fontSize: 14, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 4),
                  Text(seller.name, style: AppTypography.productName()),
                  if (!seller.isActive)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        'Неактивен',
                        style: AppTypography.productMeta().copyWith(
                          color: AppColors.saleRed,
                          fontSize: 12,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Switch(
              value: seller.isActive,
              onChanged: onToggleActive,
              activeThumbColor: AppColors.accent,
              activeTrackColor: AppColors.accent.withValues(alpha: 0.35),
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
              color: AppColors.saleRed,
            ),
          ],
        ),
      ),
    );
  }
}
