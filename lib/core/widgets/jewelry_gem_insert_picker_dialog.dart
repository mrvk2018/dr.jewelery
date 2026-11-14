import 'package:flutter/material.dart';

import '../constants/jewelry_category_subtypes.dart';
import '../constants/jewelry_gem_inserts.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

class GemInsertPickerResult {
  const GemInsertPickerResult({
    required this.catalog,
    this.legacy = const [],
  });

  final Set<String> catalog;
  final List<String> legacy;
}

/// Модальный выбор вставок (форма товара).
Future<GemInsertPickerResult?> showJewelryGemInsertPickerDialog({
  required BuildContext context,
  required Set<String> initialCatalog,
  Iterable<String> initialLegacy = const [],
}) {
  return showDialog<GemInsertPickerResult>(
    context: context,
    builder: (dialogContext) {
      return _GemInsertPickerDialogBody(
        title: 'Вставки',
        initialCatalog: Set<String>.from(initialCatalog),
        initialLegacy: List<String>.from(initialLegacy),
        confirmLabel: 'Готово',
      );
    },
  );
}

class AdditionalFilterPickerResult {
  const AdditionalFilterPickerResult({required this.selectedTags});

  final Set<String> selectedTags;
}

/// «Дополнительно» в фильтре: вставки + прочие теги из thesaurus.
Future<AdditionalFilterPickerResult?> showJewelryAdditionalFilterDialog({
  required BuildContext context,
  required Set<String> initialSelection,
  List<String> extraThesaurusTags = const [],
}) {
  return showDialog<AdditionalFilterPickerResult>(
    context: context,
    builder: (dialogContext) {
      return _AdditionalFilterDialogBody(
        initialSelection: Set<String>.from(initialSelection),
        extraThesaurusTags: extraThesaurusTags,
      );
    },
  );
}

class _GemInsertPickerDialogBody extends StatefulWidget {
  const _GemInsertPickerDialogBody({
    required this.title,
    required this.initialCatalog,
    required this.initialLegacy,
    required this.confirmLabel,
  });

  final String title;
  final Set<String> initialCatalog;
  final List<String> initialLegacy;
  final String confirmLabel;

  @override
  State<_GemInsertPickerDialogBody> createState() =>
      _GemInsertPickerDialogBodyState();
}

class _GemInsertPickerDialogBodyState extends State<_GemInsertPickerDialogBody> {
  late Set<String> _catalog;
  late List<String> _legacy;

  @override
  void initState() {
    super.initState();
    _catalog = Set<String>.from(widget.initialCatalog);
    _legacy = List<String>.from(widget.initialLegacy);
  }

  void _reset() {
    setState(() {
      _catalog.clear();
      _legacy = List<String>.from(widget.initialLegacy);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(widget.title, style: AppTypography.heading(fontSize: 20)),
      content: SizedBox(
        width: _dialogWidth(context),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GemInsertCheckboxGrid(
                selected: _catalog,
                onToggle: (label) {
                  setState(() => toggleJewelryGemInsert(_catalog, label));
                },
              ),
              if (_legacy.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Значения со склада (сохранятся при записи)',
                  style: AppTypography.productMeta().copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _legacy
                      .map(
                        (v) => Chip(
                          label: Text(v),
                          backgroundColor: AppColors.cardBackground,
                        ),
                      )
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _reset, child: const Text('Сбросить')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              GemInsertPickerResult(catalog: _catalog, legacy: _legacy),
            );
          },
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.textOnPrimary,
          ),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _AdditionalFilterDialogBody extends StatefulWidget {
  const _AdditionalFilterDialogBody({
    required this.initialSelection,
    required this.extraThesaurusTags,
  });

  final Set<String> initialSelection;
  final List<String> extraThesaurusTags;

  @override
  State<_AdditionalFilterDialogBody> createState() =>
      _AdditionalFilterDialogBodyState();
}

class _AdditionalFilterDialogBodyState extends State<_AdditionalFilterDialogBody> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set<String>.from(widget.initialSelection);
  }

  void _reset() => setState(() => _selected.clear());

  void _toggleGem(String label) {
    setState(() => toggleJewelryGemInsert(_selected, label));
  }

  void _toggleExtra(String label) {
    setState(() {
      if (_selected.contains(label)) {
        _selected.remove(label);
      } else {
        _selected.add(label);
      }
    });
  }

  void _toggleSubtypeTag(String tag) {
    setState(() {
      if (_selected.contains(tag)) {
        _selected.remove(tag);
      } else {
        _selected.add(tag);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final extras = widget.extraThesaurusTags;

    return AlertDialog(
      backgroundColor: AppColors.background,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Дополнительно', style: AppTypography.heading(fontSize: 20)),
      content: SizedBox(
        width: _dialogWidth(context),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Вставки',
                style: AppTypography.productMeta().copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              GemInsertCheckboxGrid(
                selected: _selected,
                onToggle: _toggleGem,
              ),
              const SizedBox(height: 20),
              Text(
                'Вид изделия',
                style: AppTypography.productMeta().copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              JewelrySubtypeCheckboxGrid(
                options: kJewelrySubtypeFilterOptions,
                selectedTags: _selected,
                onToggleTag: _toggleSubtypeTag,
              ),
              if (extras.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  'Прочее / теги',
                  style: AppTypography.productMeta().copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: extras.map((word) {
                    final checked = _selected.contains(word);
                    return FilterChip(
                      label: Text(word),
                      selected: checked,
                      onSelected: (_) => _toggleExtra(word),
                      selectedColor: AppColors.accent.withValues(alpha: 0.25),
                      checkmarkColor: AppColors.accent,
                      side: const BorderSide(color: AppColors.border),
                    );
                  }).toList(),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _reset, child: const Text('Сбросить')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              AdditionalFilterPickerResult(selectedTags: _selected),
            );
          },
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.textOnPrimary,
          ),
          child: const Text('Применить'),
        ),
      ],
    );
  }
}

class JewelrySubtypeCheckboxGrid extends StatelessWidget {
  const JewelrySubtypeCheckboxGrid({
    super.key,
    required this.options,
    required this.selectedTags,
    required this.onToggleTag,
  });

  final List<JewelrySubtypeFilterOption> options;
  final Set<String> selectedTags;
  final ValueChanged<String> onToggleTag;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 720 ? 3 : (width >= 420 ? 2 : 1);
        final rowCount = (options.length / columns).ceil();

        return Column(
          children: List.generate(rowCount, (rowIndex) {
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(columns, (colIndex) {
                  final itemIndex = rowIndex * columns + colIndex;
                  if (itemIndex >= options.length) {
                    return const Expanded(child: SizedBox());
                  }
                  final option = options[itemIndex];
                  final checked = selectedTags.contains(option.filterTag);
                  return Expanded(
                    child: _GemInsertCheckRow(
                      label: option.label,
                      checked: checked,
                      onChanged: () => onToggleTag(option.filterTag),
                    ),
                  );
                }),
              ),
            );
          }),
        );
      },
    );
  }
}

class GemInsertCheckboxGrid extends StatelessWidget {
  const GemInsertCheckboxGrid({
    super.key,
    required this.selected,
    required this.onToggle,
  });

  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 720 ? 3 : (width >= 420 ? 2 : 1);
        final items = kJewelryGemInserts;
        final rowCount = (items.length / columns).ceil();

        return Column(
          children: List.generate(rowCount, (rowIndex) {
            return IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(columns, (colIndex) {
                  final itemIndex = rowIndex * columns + colIndex;
                  if (itemIndex >= items.length) {
                    return const Expanded(child: SizedBox());
                  }
                  final label = items[itemIndex];
                  return Expanded(
                    child: _GemInsertCheckRow(
                      label: label,
                      checked: selected.contains(label),
                      onChanged: () => onToggle(label),
                    ),
                  );
                }),
              ),
            );
          }),
        );
      },
    );
  }
}

class _GemInsertCheckRow extends StatelessWidget {
  const _GemInsertCheckRow({
    required this.label,
    required this.checked,
    required this.onChanged,
  });

  final String label;
  final bool checked;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onChanged,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: checked,
                onChanged: (_) => onChanged(),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                style: AppTypography.productMeta().copyWith(fontSize: 13),
                softWrap: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

double _dialogWidth(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  if (width >= 900) return 640;
  if (width >= 600) return width * 0.85;
  return width * 0.92;
}