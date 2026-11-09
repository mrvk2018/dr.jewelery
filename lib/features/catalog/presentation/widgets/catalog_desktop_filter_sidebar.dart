import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/won_format.dart';
import '../../domain/models/catalog_constants.dart';

/// Боковая панель фильтров каталога (desktop, ≥960px).
class CatalogDesktopFilterSidebar extends StatefulWidget {
  const CatalogDesktopFilterSidebar({
    super.key,
    required this.draftFilters,
    required this.onDraftChanged,
    required this.onClientPreview,
    required this.onApply,
    required this.onReset,
    required this.resultCount,
  });

  final CatalogFilterState draftFilters;
  final ValueChanged<CatalogFilterState> onDraftChanged;
  final ValueChanged<CatalogFilterState> onClientPreview;
  final VoidCallback onApply;
  final VoidCallback onReset;
  final int resultCount;

  @override
  State<CatalogDesktopFilterSidebar> createState() =>
      _CatalogDesktopFilterSidebarState();
}

class _CatalogDesktopFilterSidebarState extends State<CatalogDesktopFilterSidebar> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController =
        TextEditingController(text: widget.draftFilters.localSearchQuery);
  }

  @override
  void didUpdateWidget(covariant CatalogDesktopFilterSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.draftFilters.localSearchQuery;
    if (next != _searchController.text) {
      _searchController.text = next;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _emit(CatalogFilterState next, {bool previewClient = false}) {
    widget.onDraftChanged(next);
    if (previewClient) {
      widget.onClientPreview(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final draftFilters = widget.draftFilters;
    return Material(
      color: AppColors.cardBackground,
      child: Container(
        width: 300,
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: AppColors.border)),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Фильтры',
                        style: AppTypography.heading(fontSize: 20),
                      ),
                    ),
                    TextButton(
                      onPressed: widget.onReset,
                      child: const Text('Сбросить'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  children: [
                    Text(
                      'Поиск',
                      style: AppTypography.caption(
                        fontWeight: FontWeight.w600,
                      ).copyWith(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _searchController,
                      textInputAction: TextInputAction.search,
                      decoration: InputDecoration(
                        hintText: 'SKU (поиск на сервере)',
                        filled: true,
                        fillColor: AppColors.background,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                      onChanged: (value) {
                        _emit(
                          draftFilters.copyWith(localSearchQuery: value),
                        );
                      },
                      onSubmitted: (_) => widget.onApply(),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Категория',
                      style: AppTypography.caption(
                        fontWeight: FontWeight.w600,
                      ).copyWith(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    _ChipWrap(
                      options: CatalogCategories.items,
                      selected: draftFilters.selectedCategories,
                      onToggle: (value) {
                        final updated = Set<String>.from(
                          draftFilters.selectedCategories,
                        );
                        if (updated.contains(value)) {
                          updated.remove(value);
                        } else {
                          updated.add(value);
                        }
                        _emit(draftFilters.copyWith(selectedCategories: updated));
                      },
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Металл',
                      style: AppTypography.caption(
                        fontWeight: FontWeight.w600,
                      ).copyWith(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    _ChipWrap(
                      options: CatalogMetalFamilies.items,
                      selected: draftFilters.selectedMetalFamilies,
                      onToggle: (value) {
                        final updated = Set<String>.from(
                          draftFilters.selectedMetalFamilies,
                        );
                        if (updated.contains(value)) {
                          updated.remove(value);
                        } else {
                          updated.add(value);
                        }
                        _emit(
                          draftFilters.copyWith(selectedMetalFamilies: updated),
                          previewClient: true,
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    _ChipWrap(
                      options: CatalogMetals.items,
                      selected: draftFilters.selectedMetals,
                      onToggle: (value) {
                        final updated = Set<String>.from(
                          draftFilters.selectedMetals,
                        );
                        if (updated.contains(value)) {
                          updated.remove(value);
                        } else {
                          updated.add(value);
                        }
                        _emit(draftFilters.copyWith(selectedMetals: updated));
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Проба',
                      style: AppTypography.caption(
                        fontWeight: FontWeight.w600,
                      ).copyWith(fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    _ChipWrap(
                      options: CatalogFineness.items,
                      selected: draftFilters.selectedFineness,
                      onToggle: (value) {
                        final updated = Set<String>.from(
                          draftFilters.selectedFineness,
                        );
                        if (updated.contains(value)) {
                          updated.remove(value);
                        } else {
                          updated.add(value);
                        }
                        _emit(
                          draftFilters.copyWith(selectedFineness: updated),
                          previewClient: true,
                        );
                      },
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Цена (₩)',
                      style: AppTypography.caption(
                        fontWeight: FontWeight.w600,
                      ).copyWith(fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${formatWon(draftFilters.priceMinKrw)} — '
                      '${formatWon(draftFilters.priceMaxKrw)}',
                      style: AppTypography.caption(
                        color: AppColors.textSecondary,
                      ).copyWith(fontSize: 12),
                    ),
                    RangeSlider(
                      values: RangeValues(
                        draftFilters.priceMinKrw.toDouble(),
                        draftFilters.priceMaxKrw.toDouble(),
                      ),
                      min: CatalogDesktopFilterBounds.priceMinKrw.toDouble(),
                      max: CatalogDesktopFilterBounds.priceMaxKrw.toDouble(),
                      divisions: 100,
                      labels: RangeLabels(
                        formatWon(draftFilters.priceMinKrw),
                        formatWon(draftFilters.priceMaxKrw),
                      ),
                      onChanged: (range) {
                        final next = draftFilters.copyWith(
                          priceMinKrw: range.start.round(),
                          priceMaxKrw: range.end.round(),
                        );
                        _emit(next, previewClient: true);
                      },
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Вес (г)',
                      style: AppTypography.caption(
                        fontWeight: FontWeight.w600,
                      ).copyWith(fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${draftFilters.weightMinGrams.toStringAsFixed(1)} — '
                      '${draftFilters.weightMaxGrams.toStringAsFixed(1)} г',
                      style: AppTypography.caption(
                        color: AppColors.textSecondary,
                      ).copyWith(fontSize: 12),
                    ),
                    RangeSlider(
                      values: RangeValues(
                        draftFilters.weightMinGrams,
                        draftFilters.weightMaxGrams,
                      ),
                      min: CatalogDesktopFilterBounds.weightMinGrams,
                      max: CatalogDesktopFilterBounds.weightMaxGrams,
                      divisions: 100,
                      onChanged: (range) {
                        final next = draftFilters.copyWith(
                          weightMinGrams: range.start,
                          weightMaxGrams: range.end,
                        );
                        _emit(next, previewClient: true);
                      },
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: SizedBox(
                  height: 48,
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: widget.onApply,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.textOnPrimary,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      widget.resultCount > 0
                          ? 'Применить (${widget.resultCount})'
                          : 'Применить',
                      style: AppTypography.caption(
                        color: AppColors.textOnPrimary,
                        fontWeight: FontWeight.w700,
                      ).copyWith(fontSize: 15),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChipWrap extends StatelessWidget {
  const _ChipWrap({
    required this.options,
    required this.selected,
    required this.onToggle,
  });

  final List<String> options;
  final Set<String> selected;
  final ValueChanged<String> onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in options)
          FilterChip(
            label: Text(option),
            selected: selected.contains(option),
            onSelected: (_) => onToggle(option),
            selectedColor: AppColors.accent.withValues(alpha: 0.2),
            checkmarkColor: AppColors.primary,
            side: BorderSide(
              color: selected.contains(option)
                  ? AppColors.accent
                  : AppColors.border,
            ),
          ),
      ],
    );
  }
}
