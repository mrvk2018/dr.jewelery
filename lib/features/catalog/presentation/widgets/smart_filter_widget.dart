import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/services/database_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// Двухуровневая фильтрация витрины (Supabase RPC `get_advanced_faceted_products`).
class SmartFilterWidget extends StatefulWidget {
  SmartFilterWidget({
    super.key,
    required this.onFilterApplied,
    DatabaseService? database,
    this.goldGramPrice = 95000.0,
    this.silverGramPrice = 3500.0,
  }) : database = database ?? DatabaseService.create();

  final DatabaseService database;
  final void Function(List<Map<String, dynamic>> products) onFilterApplied;
  final double goldGramPrice;
  final double silverGramPrice;

  static const List<String> baseFilterLabels = [
    'Золото',
    'Серебро',
    'Кольца',
    'Серьги',
    'Цепи',
    'Подвески',
    'Браслеты',
  ];

  @override
  State<SmartFilterWidget> createState() => _SmartFilterWidgetState();
}

class _SmartFilterWidgetState extends State<SmartFilterWidget> {
  final _minPriceController = TextEditingController();
  final _maxPriceController = TextEditingController();

  final Set<String> _selectedBaseTags = {};
  final Set<String> _selectedSlangTags = {};

  bool _isApplying = false;

  @override
  void dispose() {
    _minPriceController.dispose();
    _maxPriceController.dispose();
    super.dispose();
  }

  double? _parsePrice(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'[^\d.]'), '');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  Future<void> _applyFilter() async {
    if (_isApplying) return;
    setState(() => _isApplying = true);
    try {
      final products = await widget.database.fetchFacetedProducts(
        baseTags: _selectedBaseTags.toList(),
        advancedTags: _selectedSlangTags.toList(),
        minPrice: _parsePrice(_minPriceController.text),
        maxPrice: _parsePrice(_maxPriceController.text),
        goldGramPrice: widget.goldGramPrice,
        silverGramPrice: widget.silverGramPrice,
      );
      if (!mounted) return;
      widget.onFilterApplied(products);
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

  void _toggleBaseTag(String label) {
    setState(() {
      if (_selectedBaseTags.contains(label)) {
        _selectedBaseTags.remove(label);
      } else {
        _selectedBaseTags.add(label);
      }
    });
    _applyFilter();
  }

  Future<void> _openSlangDialog() async {
    final slangWords = await widget.database.fetchJewelryThesaurusSlang();
    if (!mounted) return;

    final draftSelection = Set<String>.from(_selectedSlangTags);

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: AppColors.background,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                'Дополнительный сленг',
                style: AppTypography.heading(fontSize: 20),
              ),
              content: SizedBox(
                width: _dialogWidth(context),
                child: slangWords.isEmpty
                    ? Text(
                        'Список сленга пуст или недоступен. '
                        'Проверьте RLS для jewelry_thesaurus.',
                        style: AppTypography.productMeta(),
                      )
                    : SingleChildScrollView(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: slangWords.map((word) {
                            final selected = draftSelection.contains(word);
                            return FilterChip(
                              label: Text(word),
                              selected: selected,
                              onSelected: (value) {
                                setDialogState(() {
                                  if (value) {
                                    draftSelection.add(word);
                                  } else {
                                    draftSelection.remove(word);
                                  }
                                });
                              },
                              selectedColor:
                                  AppColors.accent.withValues(alpha: 0.25),
                              checkmarkColor: AppColors.accent,
                              side: const BorderSide(color: AppColors.border),
                            );
                          }).toList(),
                        ),
                      ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Отмена'),
                ),
                FilledButton(
                  onPressed: () {
                    setState(() {
                      _selectedSlangTags
                        ..clear()
                        ..addAll(draftSelection);
                    });
                    Navigator.of(dialogContext).pop();
                    _applyFilter();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textOnPrimary,
                  ),
                  child: const Text('Принять сленг'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  double _dialogWidth(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    if (width >= 900) return 560;
    if (width >= 600) return width * 0.75;
    return width * 0.92;
  }

  @override
  Widget build(BuildContext context) {
    final maxContentWidth = MediaQuery.sizeOf(context).width.clamp(320.0, 1200.0);

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxContentWidth),
        child: Material(
          color: AppColors.cardBackground,
          elevation: 0,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Фильтр витрины',
                  style: AppTypography.heading(fontSize: 18),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 520;
                    final priceFields = [
                      Expanded(
                        child: _PriceField(
                          controller: _minPriceController,
                          label: 'От (₩)',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _PriceField(
                          controller: _maxPriceController,
                          label: 'До (₩)',
                        ),
                      ),
                    ];
                    if (isWide) {
                      return Row(children: priceFields);
                    }
                    return Column(
                      children: [
                        _PriceField(
                          controller: _minPriceController,
                          label: 'От (₩)',
                        ),
                        const SizedBox(height: 12),
                        _PriceField(
                          controller: _maxPriceController,
                          label: 'До (₩)',
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: SmartFilterWidget.baseFilterLabels.map((label) {
                    final selected = _selectedBaseTags.contains(label);
                    return FilterChip(
                      label: Text(label),
                      selected: selected,
                      onSelected: (_) => _toggleBaseTag(label),
                      selectedColor: AppColors.accent.withValues(alpha: 0.25),
                      checkmarkColor: AppColors.accent,
                      side: const BorderSide(color: AppColors.border),
                    );
                  }).toList(),
                ),
                if (_selectedSlangTags.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Сленг: ${_selectedSlangTags.join(', ')}',
                    style: AppTypography.productMeta().copyWith(fontSize: 12),
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  alignment: WrapAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _isApplying ? null : _openSlangDialog,
                      icon: const Icon(Icons.tune_rounded, size: 20),
                      label: const Text('Дополнительно'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _isApplying ? null : _applyFilter,
                      icon: _isApplying
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.search_rounded, size: 20),
                      label: Text(_isApplying ? 'Загрузка…' : 'Показать результаты'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: AppColors.textOnAccent,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PriceField extends StatelessWidget {
  const _PriceField({
    required this.controller,
    required this.label,
  });

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: AppColors.background,
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
