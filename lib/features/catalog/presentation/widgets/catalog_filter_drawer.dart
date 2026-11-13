import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/l10n/localized_text.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/models/catalog_constants.dart';
import '../../domain/utils/catalog_metal_facet_utils.dart';

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
                    title: 'Цена (₩)',
                    initiallyExpanded: true,
                    child: _PriceRangeFields(
                      minKrw: draftFilters.priceMinKrw,
                      maxKrw: draftFilters.priceMaxKrw,
                      onChanged: (minKrw, maxKrw) {
                        onDraftChanged(
                          draftFilters.copyWith(
                            priceMinKrw: minKrw,
                            priceMaxKrw: maxKrw,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 8),
                  _FilterExpansionSection(
                    title: 'Размер',
                    child: _SizeSelector(
                      selectedSizes: draftFilters.selectedSizes,
                      onToggle: (size) {
                        final updated = Set<double>.from(
                          draftFilters.selectedSizes,
                        );
                        if (updated.contains(size)) {
                          updated.remove(size);
                        } else {
                          updated.add(size);
                        }
                        onDraftChanged(
                          draftFilters.copyWith(selectedSizes: updated),
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
                        final updated = toggleCatalogMetalFacet(
                          draftFilters.selectedMetals,
                          value,
                        );
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
    required this.selectedSizes,
    required this.onToggle,
  });

  final Set<double> selectedSizes;
  final ValueChanged<double> onToggle;

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
          final isSelected = selectedSizes.contains(size);
          final label = size % 1 == 0 ? size.toInt().toString() : '$size';

          return Material(
            color: isSelected ? AppColors.primary : AppColors.cardBackground,
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: () => onToggle(size),
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
            label: LocalizedText.attribute(
              option,
              languageCode: context.langCode,
            ),
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

class _PriceRangeFields extends StatefulWidget {
  const _PriceRangeFields({
    required this.minKrw,
    required this.maxKrw,
    required this.onChanged,
  });

  final int minKrw;
  final int maxKrw;
  final void Function(int minKrw, int maxKrw) onChanged;

  @override
  State<_PriceRangeFields> createState() => _PriceRangeFieldsState();
}

class _PriceRangeFieldsState extends State<_PriceRangeFields> {
  late final TextEditingController _minController;
  late final TextEditingController _maxController;

  @override
  void initState() {
    super.initState();
    _minController = TextEditingController(
      text: _formatPrice(widget.minKrw),
    );
    _maxController = TextEditingController(
      text: _formatPrice(widget.maxKrw),
    );
  }

  @override
  void didUpdateWidget(covariant _PriceRangeFields oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.minKrw != widget.minKrw) {
      _minController.text = _formatPrice(widget.minKrw);
    }
    if (oldWidget.maxKrw != widget.maxKrw) {
      _maxController.text = _formatPrice(widget.maxKrw);
    }
  }

  @override
  void dispose() {
    _minController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  String _formatPrice(int value) {
    if (value <= CatalogDesktopFilterBounds.priceMinKrw) return '';
    return '$value';
  }

  int _parsePrice(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) return CatalogDesktopFilterBounds.priceMinKrw;
    return int.tryParse(digits) ?? CatalogDesktopFilterBounds.priceMinKrw;
  }

  void _emit() {
    var minKrw = _parsePrice(_minController.text);
    var maxKrw = _parsePrice(_maxController.text);
    if (maxKrw == CatalogDesktopFilterBounds.priceMinKrw) {
      maxKrw = CatalogDesktopFilterBounds.priceMaxKrw;
    }
    if (minKrw > maxKrw) {
      final swap = minKrw;
      minKrw = maxKrw;
      maxKrw = swap;
    }
    widget.onChanged(minKrw, maxKrw);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _minController,
            keyboardType: TextInputType.number,
            onChanged: (_) => _emit(),
            decoration: InputDecoration(
              labelText: 'От',
              hintText: '0',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _maxController,
            keyboardType: TextInputType.number,
            onChanged: (_) => _emit(),
            decoration: InputDecoration(
              labelText: 'До',
              hintText: 'Любая',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              isDense: true,
            ),
          ),
        ),
      ],
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
