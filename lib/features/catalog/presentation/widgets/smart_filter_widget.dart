import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/services/database_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// Фасетная фильтрация витрины (RPC `get_advanced_faceted_products`).
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

  static const String goldUmbrella = 'Золото';

  static const List<String> metalFilterLabels = [
    goldUmbrella,
    'Красное золото',
    'Жёлтое золото',
    'Белое золото',
    'Серебро',
  ];

  static const List<String> goldColorMetalLabels = [
    'Красное золото',
    'Жёлтое золото',
    'Белое золото',
  ];

  /// Значения `products.category` (склад DrJaw / ручной ввод).
  static const List<String> categoryFilterLabels = [
    'Кольцо',
    'Серьги',
    'Цепь',
    'Подвеска',
    'Браслет (женский)',
    'Браслет (мужской)',
  ];

  @override
  State<SmartFilterWidget> createState() => _SmartFilterWidgetState();
}

class _SmartFilterWidgetState extends State<SmartFilterWidget> {
  final _minPriceController = TextEditingController();
  final _maxPriceController = TextEditingController();
  final _skuController = TextEditingController();
  final _weightController = TextEditingController();

  final Set<String> _selectedMetalTags = {};
  final Set<String> _selectedCategoryTags = {};
  final Set<String> _selectedSlangTags = {};

  bool _isApplying = false;
  int _applyGeneration = 0;

  @override
  void dispose() {
    _minPriceController.dispose();
    _maxPriceController.dispose();
    _skuController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  double? _parsePrice(String raw) {
    final cleaned = raw.trim().replaceAll(RegExp(r'[^\d.]'), '');
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  double? _parseExactWeight(String raw) {
    final normalized = raw.trim().replaceAll(',', '.');
    if (normalized.isEmpty) return null;
    return double.tryParse(normalized);
  }

  String? _parseSkuQuery() {
    final q = _skuController.text.trim();
    if (q.isEmpty) return null;
    return q;
  }

  void _submitFilterField(String _) => unawaited(_applyFilter());

  Future<void> _applyFilter() async {
    final generation = ++_applyGeneration;
    if (mounted) setState(() => _isApplying = true);
    try {
      final products = await widget.database.fetchFacetedProducts(
        metalTags: _selectedMetalTags.toList(),
        categoryTags: _selectedCategoryTags.toList(),
        advancedTags: _selectedSlangTags.toList(),
        minPrice: _parsePrice(_minPriceController.text),
        maxPrice: _parsePrice(_maxPriceController.text),
        goldGramPrice: widget.goldGramPrice,
        silverGramPrice: widget.silverGramPrice,
        exactWeight: _parseExactWeight(_weightController.text),
        skuQuery: _parseSkuQuery(),
      );
      if (!mounted || generation != _applyGeneration) return;
      widget.onFilterApplied(products);
    } finally {
      if (mounted && generation == _applyGeneration) {
        setState(() => _isApplying = false);
      }
    }
  }

  void _toggleMetalTag(String label) {
    setState(() {
      if (_selectedMetalTags.contains(label)) {
        _selectedMetalTags.remove(label);
      } else {
        _selectedMetalTags.add(label);
        if (label == SmartFilterWidget.goldUmbrella) {
          _selectedMetalTags.removeAll(SmartFilterWidget.goldColorMetalLabels);
        } else if (SmartFilterWidget.goldColorMetalLabels.contains(label)) {
          _selectedMetalTags.remove(SmartFilterWidget.goldUmbrella);
        }
      }
    });
    _applyFilter();
  }

  void _toggleCategoryTag(String label) {
    setState(() {
      if (_selectedCategoryTags.contains(label)) {
        _selectedCategoryTags.remove(label);
      } else {
        _selectedCategoryTags.add(label);
      }
    });
    _applyFilter();
  }

  Future<void> _resetFilter() async {
    setState(() {
      _selectedMetalTags.clear();
      _selectedCategoryTags.clear();
      _selectedSlangTags.clear();
      _minPriceController.clear();
      _maxPriceController.clear();
      _skuController.clear();
      _weightController.clear();
    });
    await _applyFilter();
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
                        child: _FilterTextField(
                          controller: _minPriceController,
                          label: 'От (₩)',
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onSubmitted: _submitFilterField,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _FilterTextField(
                          controller: _maxPriceController,
                          label: 'До (₩)',
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onSubmitted: _submitFilterField,
                        ),
                      ),
                    ];

                    final skuWeightFields = [
                      Expanded(
                        child: _FilterTextField(
                          controller: _skuController,
                          label: 'Артикул (SKU)',
                          onSubmitted: _submitFilterField,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _FilterTextField(
                          controller: _weightController,
                          label: 'Вес, г',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.,]'),
                            ),
                          ],
                          onSubmitted: _submitFilterField,
                        ),
                      ),
                    ];

                    if (isWide) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(children: priceFields),
                          const SizedBox(height: 12),
                          Row(children: skuWeightFields),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        _FilterTextField(
                          controller: _minPriceController,
                          label: 'От (₩)',
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onSubmitted: _submitFilterField,
                        ),
                        const SizedBox(height: 12),
                        _FilterTextField(
                          controller: _maxPriceController,
                          label: 'До (₩)',
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          onSubmitted: _submitFilterField,
                        ),
                        const SizedBox(height: 12),
                        _FilterTextField(
                          controller: _skuController,
                          label: 'Артикул (SKU)',
                          onSubmitted: _submitFilterField,
                        ),
                        const SizedBox(height: 12),
                        _FilterTextField(
                          controller: _weightController,
                          label: 'Вес, г',
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9.,]'),
                            ),
                          ],
                          onSubmitted: _submitFilterField,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                _FacetChipSection(
                  title: 'Металл',
                  labels: SmartFilterWidget.metalFilterLabels,
                  selected: _selectedMetalTags,
                  onToggle: _toggleMetalTag,
                ),
                const SizedBox(height: 14),
                _FacetChipSection(
                  title: 'Категория',
                  labels: SmartFilterWidget.categoryFilterLabels,
                  selected: _selectedCategoryTags,
                  onToggle: _toggleCategoryTag,
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
                    OutlinedButton.icon(
                      onPressed: _isApplying ? null : _resetFilter,
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      label: const Text('Сбросить'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
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
                      label: Text(
                        _isApplying ? 'Загрузка…' : 'Показать результаты',
                      ),
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

class _FacetChipSection extends StatelessWidget {
  const _FacetChipSection({
    required this.title,
    required this.labels,
    required this.selected,
    required this.onToggle,
  });

  final String title;
  final List<String> labels;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: AppTypography.productMeta().copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: labels.map((label) {
            final isSelected = selected.contains(label);
            return FilterChip(
              label: Text(label),
              selected: isSelected,
              onSelected: (_) => onToggle(label),
              selectedColor: AppColors.accent.withValues(alpha: 0.25),
              checkmarkColor: AppColors.accent,
              side: const BorderSide(color: AppColors.border),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _FilterTextField extends StatelessWidget {
  const _FilterTextField({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.inputFormatters,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onSubmitted: onSubmitted,
      textInputAction: TextInputAction.search,
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
