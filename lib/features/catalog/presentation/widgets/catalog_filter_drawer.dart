import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/models/catalog_constants.dart';

/// Выдвижная панель фильтров каталога (EndDrawer).
class CatalogFilterDrawer extends StatelessWidget {
  const CatalogFilterDrawer({
    super.key,
    required this.draftFilters,
    required this.onDraftChanged,
    required this.onApply,
    required this.onReset,
    this.resultCount = 0,
  });

  final CatalogFilterState draftFilters;
  final ValueChanged<CatalogFilterState> onDraftChanged;
  final VoidCallback onApply;
  final VoidCallback onReset;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: MediaQuery.sizeOf(context).width * 0.88,
      backgroundColor: AppColors.background,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DrawerHeader(onReset: onReset),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  _FilterExpansionSection(
                    title: 'Размер',
                    child: _SizeSelector(
                      selectedSize: draftFilters.selectedSize,
                      onSelected: (size) {
                        onDraftChanged(
                          draftFilters.copyWith(
                            selectedSize: size,
                            clearSize: draftFilters.selectedSize == size,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  _FilterExpansionSection(
                    title: 'Металл',
                    initiallyExpanded: true,
                    child: _OptionWrap(
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
                        onDraftChanged(
                          draftFilters.copyWith(selectedMetals: updated),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  _FilterExpansionSection(
                    title: 'Вставка',
                    initiallyExpanded: true,
                    child: _OptionWrap(
                      options: CatalogInserts.items,
                      selected: draftFilters.selectedInserts,
                      onToggle: (value) {
                        final updated = Set<String>.from(
                          draftFilters.selectedInserts,
                        );
                        if (updated.contains(value)) {
                          updated.remove(value);
                        } else {
                          updated.add(value);
                        }
                        onDraftChanged(
                          draftFilters.copyWith(selectedInserts: updated),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            _ApplyButtonBar(
              resultCount: resultCount,
              onApply: onApply,
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({required this.onReset});

  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Фильтры',
              style: AppTypography.heading(fontSize: 22),
            ),
          ),
          TextButton(
            onPressed: onReset,
            child: Text(
              'Сбросить',
              style: AppTypography.caption(
                color: AppColors.accent,
                fontWeight: FontWeight.w600,
              ).copyWith(fontSize: 13),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded),
            color: AppColors.textPrimary,
          ),
        ],
      ),
    );
  }
}

class _FilterExpansionSection extends StatelessWidget {
  const _FilterExpansionSection({
    required this.title,
    required this.child,
    this.initiallyExpanded = false,
  });

  final String title;
  final Widget child;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: Text(
          title,
          style: AppTypography.caption(
            fontWeight: FontWeight.w600,
          ).copyWith(fontSize: 15, color: AppColors.textPrimary),
        ),
        iconColor: AppColors.textPrimary,
        collapsedIconColor: AppColors.textSecondary,
        children: [child],
      ),
    );
  }
}

class _SizeSelector extends StatelessWidget {
  const _SizeSelector({
    required this.selectedSize,
    required this.onSelected,
  });

  final double? selectedSize;
  final ValueChanged<double> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: CatalogRingSizes.items.length,
        separatorBuilder: (context, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final size = CatalogRingSizes.items[index];
          final isSelected = selectedSize == size;
          final label = size % 1 == 0 ? size.toInt().toString() : '$size';

          return Material(
            color: isSelected ? AppColors.primary : AppColors.cardBackground,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: () => onSelected(size),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.border,
                  ),
                ),
                child: Text(
                  label,
                  style: AppTypography.caption(
                    color: isSelected
                        ? AppColors.textOnPrimary
                        : AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ).copyWith(fontSize: 13),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OptionWrap extends StatelessWidget {
  const _OptionWrap({
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
          _FilterOptionChip(
            label: option,
            isSelected: selected.contains(option),
            onTap: () => onToggle(option),
          ),
      ],
    );
  }
}

class _FilterOptionChip extends StatelessWidget {
  const _FilterOptionChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? AppColors.accent.withValues(alpha: 0.15)
          : AppColors.cardBackground,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? AppColors.accent : AppColors.border,
            ),
          ),
          child: Text(
            label,
            style: AppTypography.caption(
              color: isSelected ? AppColors.primary : AppColors.textPrimary,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            ).copyWith(fontSize: 13),
          ),
        ),
      ),
    );
  }
}

class _ApplyButtonBar extends StatelessWidget {
  const _ApplyButtonBar({
    required this.resultCount,
    required this.onApply,
  });

  final int resultCount;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SizedBox(
        height: 48,
        width: double.infinity,
        child: ElevatedButton(
          onPressed: onApply,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.textOnPrimary,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: AppTypography.caption(
              color: AppColors.textOnPrimary,
              fontWeight: FontWeight.w700,
            ).copyWith(fontSize: 15),
          ),
          child: Text(
            resultCount > 0
                ? 'Показать результаты ($resultCount)'
                : 'Показать результаты',
          ),
        ),
      ),
    );
  }
}
