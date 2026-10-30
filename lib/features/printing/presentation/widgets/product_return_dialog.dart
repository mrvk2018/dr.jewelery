import 'package:flutter/material.dart';

import '../../../../core/services/database_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/won_format.dart';

/// Поиск проданных позиций (RPC) и возврат на витрину.
class ProductReturnDialog extends StatefulWidget {
  const ProductReturnDialog({
    super.key,
    required this.database,
  });

  final DatabaseService database;

  static Future<void> show(
    BuildContext context, {
    required DatabaseService database,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => ProductReturnDialog(database: database),
    );
  }

  @override
  State<ProductReturnDialog> createState() => _ProductReturnDialogState();
}

class _ProductReturnDialogState extends State<ProductReturnDialog> {
  final _skuController = TextEditingController();
  final _weightController = TextEditingController();

  int? _daysLimit;
  bool _searching = false;
  bool _returnBusy = false;
  List<Map<String, dynamic>> _results = const [];

  @override
  void dispose() {
    _skuController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.saleRed : AppColors.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _runSearch() async {
    final sku = _skuController.text.trim();
    final weightText = _weightController.text.trim().replaceAll(',', '.');
    final weight = weightText.isEmpty ? null : double.tryParse(weightText);

    if (sku.isEmpty && weight == null && _daysLimit == null) {
      _snack(
        'Укажите артикул, вес или период (не «За всё время» без других фильтров)',
        error: true,
      );
      return;
    }

    setState(() {
      _searching = true;
      _results = const [];
    });

    try {
      final rows = await widget.database.searchSoldProducts(
        sku: sku.isEmpty ? null : sku,
        weight: weight,
        daysLimit: _daysLimit,
      );
      if (!mounted) return;
      setState(() => _results = rows);
      if (rows.isEmpty) {
        _snack('Ничего не найдено по заданным фильтрам');
      }
    } catch (error) {
      if (!mounted) return;
      _snack('Ошибка поиска: $error', error: true);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _processReturn(Map<String, dynamic> row) async {
    final sku = row['sku']?.toString().trim() ?? '';
    if (sku.isEmpty) {
      _snack('У записи нет SKU', error: true);
      return;
    }

    setState(() => _returnBusy = true);
    try {
      await widget.database.processProductReturn(sku);
      if (!mounted) return;
      _snack('Возврат оформлен · $sku снова на витрине');
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      _snack('Не удалось оформить возврат: $error', error: true);
    } finally {
      if (mounted) setState(() => _returnBusy = false);
    }
  }

  static String _field(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value == null) return '—';
    final text = value.toString().trim();
    return text.isEmpty ? '—' : text;
  }

  static String _priceLine(Map<String, dynamic> row) {
    final raw = row['price_krw'] ?? row['sale_price'];
    if (raw is num) return formatWon(raw.toInt());
    return '—';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Возврат товара', style: AppTypography.heading(fontSize: 18)),
      content: SizedBox(
        width: 560,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _skuController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Артикул (SKU)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _weightController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Вес, г (строгое совпадение)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Text('Период продажи', style: AppTypography.productMeta()),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _PeriodChip(
                  label: '3 дня',
                  selected: _daysLimit == 3,
                  onSelected: () => setState(() => _daysLimit = 3),
                ),
                _PeriodChip(
                  label: 'Неделя',
                  selected: _daysLimit == 7,
                  onSelected: () => setState(() => _daysLimit = 7),
                ),
                _PeriodChip(
                  label: 'Месяц',
                  selected: _daysLimit == 30,
                  onSelected: () => setState(() => _daysLimit = 30),
                ),
                _PeriodChip(
                  label: '3 месяца',
                  selected: _daysLimit == 90,
                  onSelected: () => setState(() => _daysLimit = 90),
                ),
                _PeriodChip(
                  label: 'За все время',
                  selected: _daysLimit == null,
                  onSelected: () => setState(() => _daysLimit = null),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _searching || _returnBusy ? null : _runSearch,
              icon: _searching
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: Text(_searching ? 'Поиск…' : 'Найти'),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _results.isEmpty
                  ? Center(
                      child: Text(
                        'Результаты появятся после поиска',
                        style: AppTypography.productMeta(),
                      ),
                    )
                  : ListView.separated(
                      itemCount: _results.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final row = _results[index];
                        return _SoldProductReturnCard(
                          name: _field(row, 'name'),
                          sku: _field(row, 'sku'),
                          weight: _field(row, 'weight_grams'),
                          price: _priceLine(row),
                          busy: _returnBusy,
                          onReturn: () => _processReturn(row),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _returnBusy ? null : () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }
}

class _PeriodChip extends StatelessWidget {
  const _PeriodChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
    );
  }
}

class _SoldProductReturnCard extends StatelessWidget {
  const _SoldProductReturnCard({
    required this.name,
    required this.sku,
    required this.weight,
    required this.price,
    required this.busy,
    required this.onReturn,
  });

  final String name;
  final String sku;
  final String weight;
  final String price;
  final bool busy;
  final VoidCallback onReturn;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(name, style: AppTypography.heading(fontSize: 15)),
            const SizedBox(height: 4),
            Text('SKU: $sku', style: AppTypography.productMeta()),
            Text('Вес: $weight г · $price', style: AppTypography.productMeta()),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: busy ? null : onReturn,
              icon: const Text('🔄', style: TextStyle(fontSize: 18)),
              label: const Text('Оформить возврат'),
            ),
          ],
        ),
      ),
    );
  }
}
