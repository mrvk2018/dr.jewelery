import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/jewelry_gem_inserts.dart';
import '../../../../core/services/database_service.dart';
import '../../../../core/widgets/jewelry_gem_insert_picker_dialog.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/store_location_utils.dart';

/// Фасетная фильтрация витрины (RPC `get_advanced_faceted_products`).
class SmartFilterWidget extends StatefulWidget {
  SmartFilterWidget({
    super.key,
    required this.onFilterApplied,
    DatabaseService? database,
    this.goldGramPrice = 95000.0,
    this.silverGramPrice = 3500.0,
    this.compactAdminLayout = false,
  }) : database = database ?? DatabaseService.create();

  final DatabaseService database;
  final void Function(List<Map<String, dynamic>> products) onFilterApplied;
  final double goldGramPrice;
  final double silverGramPrice;

  /// Компактная вёрстка для админ-рабочего стола (сворачивание, плотные отступы).
  final bool compactAdminLayout;

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

  static const List<String> categoryFilterLabels = [
    'Кольцо',
    'Серьги',
    'Цепь',
    'Подвески',
    'Крест',
    'Колье',
    'Браслет',
    'Браслет (женский)',
    'Браслет (мужской)',
    'Пирсинг',
    'Гайтан',
    'Брошь',
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

  String? _selectedStoreLocation;

  bool _isApplying = false;
  int _applyGeneration = 0;
  bool _filterCollapsed = false;

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
        storeLocation: _selectedStoreLocation,
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
      _selectedStoreLocation = null;
    });
    await _applyFilter();
  }

  void _selectStoreFilter(String? code) {
    setState(() => _selectedStoreLocation = code);
    unawaited(_applyFilter());
  }

  Future<void> _openAdditionalFilterDialog() async {
    final slangWords = await widget.database.fetchJewelryThesaurusSlang();
    if (!mounted) return;

    final extraThesaurusTags = slangWords
        .where((word) => !isKnownJewelryGemCatalogLabel(word))
        .toList();

    final result = await showJewelryAdditionalFilterDialog(
      context: context,
      initialSelection: _selectedSlangTags,
      extraThesaurusTags: extraThesaurusTags,
    );
    if (result == null || !mounted) return;

    setState(() {
      _selectedSlangTags
        ..clear()
        ..addAll(result.selectedTags);
    });
    await _applyFilter();
  }

  int get _activeFacetCount =>
      _selectedMetalTags.length +
      _selectedCategoryTags.length +
      _selectedSlangTags.length +
      (_selectedStoreLocation != null ? 1 : 0);

  Widget _buildCompactFilterBody(double maxWidth) {
    final fourInRow = maxWidth >= 560;
    final twoInRow = maxWidth >= 360 && !fourInRow;

    Widget fieldRow(List<Widget> fields) {
      if (fourInRow) {
        return Row(children: fields);
      }
      if (twoInRow) {
        return Row(
          children: [
            Expanded(child: fields[0]),
            const SizedBox(width: 8),
            Expanded(child: fields[1]),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < fields.length; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            fields[i],
          ],
        ],
      );
    }

    final minField = _FilterTextField(
      controller: _minPriceController,
      label: 'От (₩)',
      compact: true,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onSubmitted: _submitFilterField,
    );
    final maxField = _FilterTextField(
      controller: _maxPriceController,
      label: 'До (₩)',
      compact: true,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onSubmitted: _submitFilterField,
    );
    final skuField = _FilterTextField(
      controller: _skuController,
      label: 'Артикул (SKU)',
      compact: true,
      onSubmitted: _submitFilterField,
    );
    final weightField = _FilterTextField(
      controller: _weightController,
      label: 'Вес, г',
      compact: true,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      onSubmitted: _submitFilterField,
    );

    Widget paddedExpanded(Widget child) => Expanded(child: child);

    final inputs = fourInRow
        ? Row(
            children: [
              paddedExpanded(minField),
              const SizedBox(width: 8),
              paddedExpanded(maxField),
              const SizedBox(width: 8),
              paddedExpanded(skuField),
              const SizedBox(width: 8),
              paddedExpanded(weightField),
            ],
          )
        : Column(
            children: [
              fieldRow([minField, maxField]),
              const SizedBox(height: 6),
              fieldRow([skuField, weightField]),
            ],
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        inputs,
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                runSpacing: 4,
                children: [
                  Text(
                    'Магазин',
                    style: AppTypography.productMeta().copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  _CompactFilterChip(
                    label: 'Все',
                    selected: _selectedStoreLocation == null,
                    onTap: _isApplying ? null : () => _selectStoreFilter(null),
                  ),
                  _CompactFilterChip(
                    label: 'Инчхон',
                    selected: _selectedStoreLocation == StoreLocationCode.icn,
                    onTap: _isApplying
                        ? null
                        : () => _selectStoreFilter(StoreLocationCode.icn),
                  ),
                  _CompactFilterChip(
                    label: 'Ансан',
                    selected: _selectedStoreLocation == StoreLocationCode.ans,
                    onTap: _isApplying
                        ? null
                        : () => _selectStoreFilter(StoreLocationCode.ans),
                  ),
                  Container(
                    width: 1,
                    height: 20,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    color: AppColors.border,
                  ),
                  Text(
                    'Металл',
                    style: AppTypography.productMeta().copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  ...SmartFilterWidget.metalFilterLabels.map(
                    (label) => _CompactFilterChip(
                      label: label,
                      selected: _selectedMetalTags.contains(label),
                      onTap: _isApplying ? null : () => _toggleMetalTag(label),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 6,
          runSpacing: 4,
          children: [
            Text(
              'Категория',
              style: AppTypography.productMeta().copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
            ...SmartFilterWidget.categoryFilterLabels.map(
              (label) => _CompactFilterChip(
                label: label,
                selected: _selectedCategoryTags.contains(label),
                onTap: _isApplying ? null : () => _toggleCategoryTag(label),
              ),
            ),
          ],
        ),
        if (_selectedSlangTags.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Сленг: ${_selectedSlangTags.join(', ')}',
            style: AppTypography.productMeta().copyWith(fontSize: 11),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          alignment: WrapAlignment.end,
          children: [
            _CompactActionButton(
              icon: Icons.tune_rounded,
              label: _selectedSlangTags.isEmpty
                  ? 'Дополнительно'
                  : 'Доп. (${_selectedSlangTags.length})',
              onPressed: _isApplying ? null : _openAdditionalFilterDialog,
              outlined: true,
            ),
            _CompactActionButton(
              icon: Icons.refresh_rounded,
              label: 'Сбросить',
              onPressed: _isApplying ? null : _resetFilter,
              outlined: true,
            ),
            _CompactActionButton(
              icon: Icons.search_rounded,
              label: _isApplying ? 'Загрузка…' : 'Показать',
              onPressed: _isApplying ? null : _applyFilter,
              loading: _isApplying,
              filled: true,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildLegacyBody(double maxWidth) => _buildCompactFilterBody(maxWidth);

  @override
  Widget build(BuildContext context) {
    final compact = widget.compactAdminLayout;

    final content = Material(
      color: AppColors.cardBackground,
      elevation: 0,
      borderRadius: BorderRadius.circular(compact ? 10 : 16),
      child: Container(
        padding: EdgeInsets.all(compact ? 10 : 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(compact ? 10 : 16),
          border: Border.all(color: AppColors.border),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final filterBody = compact
                ? _buildCompactFilterBody(constraints.maxWidth)
                : _buildLegacyBody(constraints.maxWidth);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Фильтр витрины',
                        style: AppTypography.heading(
                          fontSize: compact ? 14 : 18,
                        ),
                      ),
                    ),
                    if (compact && _activeFacetCount > 0)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(
                          'активно: $_activeFacetCount',
                          style: AppTypography.productMeta().copyWith(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    if (compact)
                      TextButton.icon(
                        onPressed: () =>
                            setState(() => _filterCollapsed = !_filterCollapsed),
                        icon: Icon(
                          _filterCollapsed
                              ? Icons.unfold_more
                              : Icons.unfold_less,
                          size: 18,
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                        label: Text(
                          _filterCollapsed ? 'Развернуть' : 'Свернуть',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                  ],
                ),
                if (!compact || !_filterCollapsed) ...[
                  SizedBox(height: compact ? 8 : 12),
                  filterBody,
                ],
              ],
            );
          },
        ),
      ),
    );

    if (compact) {
      return content;
    }

    final maxContentWidth = MediaQuery.sizeOf(context).width.clamp(320.0, 1200.0);
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxContentWidth),
        child: content,
      ),
    );
  }
}

class _CompactFilterChip extends StatelessWidget {
  const _CompactFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(
        label,
        style: const TextStyle(fontSize: 11),
      ),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      selected: selected,
      onSelected: onTap == null ? null : (_) => onTap!(),
      selectedColor: AppColors.accent.withValues(alpha: 0.22),
      checkmarkColor: AppColors.accent,
      side: const BorderSide(color: AppColors.border),
    );
  }
}

class _CompactActionButton extends StatelessWidget {
  const _CompactActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.outlined = false,
    this.filled = false,
    this.loading = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool outlined;
  final bool filled;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(icon, size: 16);

    final style = ButtonStyle(
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      minimumSize: const WidgetStatePropertyAll(Size(0, 32)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 12)),
    );

    if (filled) {
      return FilledButton.icon(
        onPressed: onPressed,
        style: style.copyWith(
          backgroundColor: const WidgetStatePropertyAll(AppColors.accent),
          foregroundColor: const WidgetStatePropertyAll(AppColors.textOnAccent),
        ),
        icon: child,
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: style,
      icon: child,
      label: Text(label),
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
    this.compact = false,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onSubmitted;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(compact ? 8 : 12),
      borderSide: const BorderSide(color: AppColors.border),
    );

    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onSubmitted: onSubmitted,
      textInputAction: TextInputAction.search,
      style: TextStyle(fontSize: compact ? 12 : 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(fontSize: compact ? 11 : 13),
        isDense: compact,
        contentPadding: compact
            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 10)
            : null,
        constraints: compact
            ? const BoxConstraints(minHeight: 36, maxHeight: 40)
            : null,
        filled: true,
        fillColor: AppColors.background,
        border: border,
        enabledBorder: border,
        focusedBorder: border.copyWith(
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
      ),
    );
  }
}