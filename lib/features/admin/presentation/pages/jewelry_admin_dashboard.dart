import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/services/database_service.dart';
import '../../../../shared/models/product_item.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../catalog/presentation/widgets/smart_filter_widget.dart';
import '../../../printing/application/label_print_service.dart';
import '../../../printing/domain/jewelry_label_data.dart';
import '../../../printing/domain/jewelry_label_layout.dart';
import '../../../printing/presentation/widgets/jewelry_label_preview.dart';
import '../../../printing/presentation/widgets/product_return_dialog.dart';
import '../screens/draft_intake_screen.dart';

List<String> parseAdditionalImagesField(Object? raw) {
  if (raw == null) return const [];
  if (raw is List) {
    return raw
        .map((e) => e.toString().trim())
        .where((url) => url.isNotEmpty)
        .toList();
  }
  if (raw is String) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const [];
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is List) {
        return decoded
            .map((e) => e.toString().trim())
            .where((url) => url.isNotEmpty)
            .toList();
      }
    } catch (_) {
      return const [];
    }
  }
  return const [];
}

List<String> productGalleryImageUrls(Map<String, dynamic> row) {
  final fromAdditional =
      parseAdditionalImagesField(row['additional_images']);
  if (fromAdditional.isNotEmpty) {
    return fromAdditional.take(ProductItem.maxGalleryImages).toList();
  }
  final legacyUrl = row['image_url']?.toString().trim() ?? '';
  if (legacyUrl.isNotEmpty) {
    return [legacyUrl];
  }
  return const [];
}

/// Десктопный рабочий стол «Доктор Ювелир»: витрина + медиа + KPI.
class JewelryAdminDashboard extends StatefulWidget {
  JewelryAdminDashboard({
    super.key,
    DatabaseService? database,
  }) : database = database ?? DatabaseService.create();

  final DatabaseService database;

  @override
  State<JewelryAdminDashboard> createState() => _JewelryAdminDashboardState();
}

class _JewelryAdminDashboardState extends State<JewelryAdminDashboard> {
  final LabelPrintService _labelPrintService = const LabelPrintService(
    protocol: LabelPrinterProtocol.tspl,
  );

  List<Map<String, dynamic>> _products = const [];
  Map<String, dynamic>? _selected;
  bool _initialLoading = true;
  bool _photoUploadBusy = false;

  @override
  void initState() {
    super.initState();
    _refreshCatalog();
  }

  int _stockQty(Map<String, dynamic> row) {
    return (row['stock_quantity'] as num?)?.toInt() ?? 0;
  }

  String _catalogStatus(Map<String, dynamic> row) {
    return row['status']?.toString().trim() ?? 'active';
  }

  /// Рабочий стол: только витрина в наличии (не черновики hidden, не нулевой остаток).
  bool _isShowroomRow(Map<String, dynamic> row) {
    if (_catalogStatus(row) == 'hidden') return false;
    return _stockQty(row) > 0;
  }

  String _cell(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value == null) return '—';
    final text = value.toString().trim();
    return text.isEmpty ? '—' : text;
  }

  double _weight(Map<String, dynamic> row) {
    return (row['weight_grams'] as num?)?.toDouble() ?? 0;
  }

  double _size(Map<String, dynamic> row) {
    return (row['size_value'] as num?)?.toDouble() ?? 0;
  }

  List<String> _imageUrls(Map<String, dynamic> row) =>
      productGalleryImageUrls(row);

  Future<void> _fetchAndMergeProductMedia(String sku) async {
    if (sku.isEmpty) return;

    try {
      final media = await widget.database.fetchProductMediaFieldsBySku(sku);
      if (!mounted || media == null) return;

      final selected = _selected;
      if (selected == null || _cell(selected, 'sku') != sku) return;

      setState(() {
        _selected = Map<String, dynamic>.from(selected)
          ..['additional_images'] = media['additional_images']
          ..['image_url'] = media['image_url'];
      });
    } catch (error, stackTrace) {
      debugPrint('JewelryAdminDashboard._fetchAndMergeProductMedia: $error');
      debugPrint('$stackTrace');
    }
  }

  Future<void> _selectProductRow(Map<String, dynamic> row) async {
    final sku = row['sku']?.toString().trim() ?? '';
    setState(() => _selected = row);
    await _fetchAndMergeProductMedia(sku);
  }

  Future<void> _addPhotoToSelected() async {
    final row = _selected;
    if (row == null) return;
    final sku = _cell(row, 'sku');
    if (sku == '—') return;

    final currentCount = _imageUrls(row).length;
    if (currentCount >= ProductItem.maxGalleryImages) {
      _snack('Достигнут лимит ${ProductItem.maxGalleryImages} фото', error: true);
      return;
    }

    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
    );
    if (picked == null || !mounted) return;

    setState(() => _photoUploadBusy = true);
    try {
      final bytes = await picked.readAsBytes();
      final url = await widget.database.uploadProductAdditionalImage(
        sku: sku,
        bytes: bytes,
        contentType: picked.mimeType ?? 'image/jpeg',
      );
      if (!mounted) return;
      if (url == null) {
        _snack('Не удалось загрузить фото (Storage / RLS)', error: true);
        return;
      }
      _snack('Фото ${currentCount + 1}/${ProductItem.maxGalleryImages} загружено');
      await _refreshCatalog();
    } catch (error) {
      if (!mounted) return;
      _snack('Ошибка загрузки: $error', error: true);
    } finally {
      if (mounted) setState(() => _photoUploadBusy = false);
    }
  }

  void _applyRows(List<Map<String, dynamic>> rows) {
    final active = rows.where(_isShowroomRow).toList();
    Map<String, dynamic>? selected = _selected;
    if (selected != null) {
      final sku = _cell(selected, 'sku');
      selected = null;
      for (final row in active) {
        if (_cell(row, 'sku') == sku) {
          selected = row;
          break;
        }
      }
    }
    setState(() {
      _products = active;
      _selected = selected;
    });
    if (selected != null) {
      final sku = _cell(selected, 'sku');
      if (sku != '—') {
        unawaited(_fetchAndMergeProductMedia(sku));
      }
    }
  }

  Future<void> _refreshCatalog() async {
    try {
      final rows = await widget.database.fetchAllProductRowsForAdminCatalog();
      if (!mounted) return;
      _applyRows(rows);
    } catch (error, stackTrace) {
      debugPrint('JewelryAdminDashboard._refreshCatalog failed: $error');
      debugPrint('$stackTrace');
      if (!mounted) return;
      _snack('Ошибка загрузки витрины: $error', error: true);
    } finally {
      if (mounted) setState(() => _initialLoading = false);
    }
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

  Future<void> _openDraftIntake() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DraftIntakeScreen(database: widget.database),
      ),
    );
    if (!mounted) return;
    await _refreshCatalog();
  }

  Future<void> _openAddProductDialog() async {
    await _openManualProductDialog();
  }

  Future<void> _openProductReturnDialog() async {
    await ProductReturnDialog.show(
      context,
      database: widget.database,
    );
    if (!mounted) return;
    await _refreshCatalog();
  }

  Future<void> _openEditProductDialog(Map<String, dynamic> row) async {
    await _openManualProductDialog(editProduct: row);
  }

  Future<void> _openManualProductDialog({
    Map<String, dynamic>? editProduct,
  }) async {
    final isEdit = editProduct != null;
    await showDialog<void>(
      context: context,
      builder: (context) => _ManualProductDialog(
        database: widget.database,
        editProduct: editProduct,
        onSaved: ({required bool asDraft}) async {
          if (isEdit) {
            _snack('Карточка обновлена');
          } else if (asDraft) {
            _snack('Товар успешно сохранен в черновики');
          } else {
            _snack('Товар успешно добавлен на витрину');
          }
          await _refreshCatalog();
        },
      ),
    );
  }

  Future<void> _editSelectedCard() async {
    final row = _selected;
    if (row == null) {
      _snack('Выберите товар в таблице', error: true);
      return;
    }
    await _openManualProductDialog(editProduct: row);
  }

  Future<void> _writeOffSelected() async {
    final row = _selected;
    if (row == null) {
      _snack('Выберите товар в таблице', error: true);
      return;
    }
    final sku = _cell(row, 'sku');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Списать с витрины?'),
        content: Text('SKU $sku → stock_quantity = 0'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.saleRed),
            child: const Text('Списать'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final ok = await widget.database.writeOffProductBySku(sku);
      if (!ok) {
        _snack('Списание не выполнено (RLS?)', error: true);
        return;
      }
      _snack('Товар $sku снят с витрины');
      await _refreshCatalog();
    } catch (error) {
      _snack('Ошибка списания: $error', error: true);
    }
  }

  Future<void> _markSoldSelected() async {
    final row = _selected;
    if (row == null) {
      _snack('Выберите товар в таблице', error: true);
      return;
    }
    final sku = _cell(row, 'sku');
    final productId = row['id']?.toString().trim() ?? '';
    if (productId.isEmpty) {
      _snack('У позиции нет id', error: true);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Продано'),
        content: Text(
          'Зафиксировать ручную продажу изделия $sku и перенести в историю продаж?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF1B5E20),
            ),
            child: const Text('Продано'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      final ok = await widget.database.markProductSoldByProductId(productId);
      if (!ok) {
        _snack('Продажа не зафиксирована (RLS?)', error: true);
        return;
      }
      _snack('Продажа $sku зафиксирована · история обновится на сервере');
      await _refreshCatalog();
    } catch (error) {
      _snack('Ошибка продажи: $error', error: true);
    }
  }

  Future<void> _printDuplicateLabel() async {
    final row = _selected;
    if (row == null) {
      _snack('Выберите товар в таблице', error: true);
      return;
    }

    final labelData = JewelryLabelData.fromProductMap(row);
    final sku = _cell(row, 'sku');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            'Дубликат бирки · $sku',
            style: AppTypography.heading(fontSize: 18),
          ),
          content: SingleChildScrollView(
            child: JewelryLabelPreview(data: labelData),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Печатать'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    try {
      await _labelPrintService.printLabel(labelData);
      _snack('Дубликат бирки отправлен на печать (TSPL)');
    } catch (error, stackTrace) {
      debugPrint('JewelryAdminDashboard._printDuplicateLabel failed: $error');
      debugPrint('$stackTrace');
      _snack('Ошибка печати: $error', error: true);
    }
  }

  double get _totalWeightGrams =>
      _products.fold(0.0, (sum, row) => sum + _weight(row));

  @override
  Widget build(BuildContext context) {
    final selectedSku = _selected == null ? null : _cell(_selected!, 'sku');

    return Scaffold(
      backgroundColor: AppColors.background,
      body: _initialLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TopControlBar(
                    database: widget.database,
                    onFilterApplied: _applyRows,
                    onOpenDraft: _openDraftIntake,
                    onAddProduct: _openAddProductDialog,
                    onProductReturn: _openProductReturnDialog,
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 3,
                          child: _ProductTablePanel(
                            products: _products,
                            selectedSku: selectedSku,
                            onSelect: _selectProductRow,
                            onEdit: _openEditProductDialog,
                            cell: _cell,
                            weight: _weight,
                            size: _size,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          flex: 2,
                          child: _MediaAndKpiPanel(
                            selected: _selected,
                            imageUrls: _selected == null
                                ? const []
                                : _imageUrls(_selected!),
                            totalCount: _products.length,
                            totalWeightGrams: _totalWeightGrams,
                            cell: _cell,
                            weight: _weight,
                            photoUploadBusy: _photoUploadBusy,
                            onAddPhoto: _addPhotoToSelected,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _BottomActionBar(
                    hasSelection: _selected != null,
                    onPrint: _printDuplicateLabel,
                    onEdit: _editSelectedCard,
                    onMarkSold: _markSoldSelected,
                    onWriteOff: _writeOffSelected,
                  ),
                ],
              ),
            ),
    );
  }
}

class _TopControlBar extends StatelessWidget {
  const _TopControlBar({
    required this.database,
    required this.onFilterApplied,
    required this.onOpenDraft,
    required this.onAddProduct,
    required this.onProductReturn,
  });

  final DatabaseService database;
  final void Function(List<Map<String, dynamic>> products) onFilterApplied;
  final VoidCallback onOpenDraft;
  final VoidCallback onAddProduct;
  final VoidCallback onProductReturn;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: onOpenDraft,
                  icon: const Icon(Icons.move_to_inbox_outlined),
                  label: const Text('Перейти в режим Приёмки (Черновики)'),
                ),
                OutlinedButton.icon(
                  onPressed: onProductReturn,
                  icon: const Icon(Icons.replay_outlined),
                  label: const Text('Возврат товара'),
                ),
                FilledButton.icon(
                  onPressed: onAddProduct,
                  icon: const Icon(Icons.add_circle_outline),
                  label: const Text('Добавить товар'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textOnPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SmartFilterWidget(
              database: database,
              onFilterApplied: onFilterApplied,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductTablePanel extends StatelessWidget {
  const _ProductTablePanel({
    required this.products,
    required this.selectedSku,
    required this.onSelect,
    required this.onEdit,
    required this.cell,
    required this.weight,
    required this.size,
  });

  final List<Map<String, dynamic>> products;
  final String? selectedSku;
  final ValueChanged<Map<String, dynamic>> onSelect;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final String Function(Map<String, dynamic>, String) cell;
  final double Function(Map<String, dynamic>) weight;
  final double Function(Map<String, dynamic>) size;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: products.isEmpty
          ? Center(
              child: Text(
                'Нет активных позиций (stock_quantity > 0)',
                style: AppTypography.productMeta(),
              ),
            )
          : Scrollbar(
              thumbVisibility: true,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: DataTable(
                    showCheckboxColumn: false,
                    headingRowColor: WidgetStateProperty.all(
                      AppColors.cardBackground,
                    ),
                    columns: const [
                      DataColumn(label: Text('Артикул (SKU)')),
                      DataColumn(label: Text('Металл')),
                      DataColumn(label: Text('Вес, г')),
                      DataColumn(label: Text('Размер')),
                      DataColumn(label: Text('Вставки')),
                      DataColumn(label: Text('Описание')),
                      DataColumn(label: Text('')),
                    ],
                    rows: products.map((row) {
                      final sku = cell(row, 'sku');
                      final selected = sku == selectedSku;
                      return DataRow(
                        selected: selected,
                        onSelectChanged: (_) => onSelect(row),
                        color: WidgetStateProperty.resolveWith((states) {
                          if (selected) {
                            return AppColors.accent.withValues(alpha: 0.12);
                          }
                          return null;
                        }),
                        cells: [
                          DataCell(Text(sku)),
                          DataCell(Text(cell(row, 'metal'))),
                          DataCell(Text(weight(row).toStringAsFixed(2))),
                          DataCell(Text(size(row).toStringAsFixed(2))),
                          DataCell(Text(cell(row, 'gem_inserts'))),
                          DataCell(
                            SizedBox(
                              width: 220,
                              child: Text(
                                cell(row, 'notes'),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          DataCell(
                            IconButton(
                              tooltip: 'Редактировать карточку',
                              icon: const Text('✏️', style: TextStyle(fontSize: 18)),
                              onPressed: () => onEdit(row),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
    );
  }
}

class _MediaAndKpiPanel extends StatelessWidget {
  const _MediaAndKpiPanel({
    required this.selected,
    required this.imageUrls,
    required this.totalCount,
    required this.totalWeightGrams,
    required this.cell,
    required this.weight,
    required this.photoUploadBusy,
    required this.onAddPhoto,
  });

  final Map<String, dynamic>? selected;
  final List<String> imageUrls;
  final int totalCount;
  final double totalWeightGrams;
  final String Function(Map<String, dynamic>, String) cell;
  final double Function(Map<String, dynamic>) weight;
  final bool photoUploadBusy;
  final VoidCallback onAddPhoto;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('KPI витрины (текущая выборка)', style: AppTypography.heading(fontSize: 16)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _KpiTile(
                    label: 'Позиций',
                    value: '$totalCount',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _KpiTile(
                    label: 'Суммарная масса',
                    value: '${totalWeightGrams.toStringAsFixed(2)} г',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              selected == null
                  ? 'Фото товара'
                  : 'Фото · ${cell(selected!, 'sku')}',
              style: AppTypography.heading(fontSize: 16),
            ),
            const SizedBox(height: 12),
            _ProductPhotoGrid(imageUrls: imageUrls),
            if (selected != null) ...[
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: photoUploadBusy ||
                          imageUrls.length >= ProductItem.maxGalleryImages
                      ? null
                      : onAddPhoto,
                  icon: photoUploadBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(
                    'Добавить фото (${imageUrls.length}/${ProductItem.maxGalleryImages})',
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Масса выбранного: ${weight(selected!).toStringAsFixed(2)} г',
                style: AppTypography.productMeta(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.productMeta()),
          const SizedBox(height: 4),
          Text(value, style: AppTypography.heading(fontSize: 18)),
        ],
      ),
    );
  }
}

class _ProductPhotoGrid extends StatelessWidget {
  const _ProductPhotoGrid({required this.imageUrls});

  final List<String> imageUrls;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: List.generate(ProductItem.maxGalleryImages, (index) {
        final url = index < imageUrls.length ? imageUrls[index] : null;
        return _PhotoSlot(url: url);
      }),
    );
  }
}

class _PhotoSlot extends StatelessWidget {
  const _PhotoSlot({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.cardBackground,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: url == null
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.image_not_supported_outlined,
                    color: AppColors.textSecondary.withValues(alpha: 0.5),
                  ),
                  const SizedBox(height: 4),
                  Text('Нет фото', style: AppTypography.productMeta()),
                ],
              )
            : ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  url!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.broken_image_outlined),
                ),
              ),
      ),
    );
  }
}

class _BottomActionBar extends StatelessWidget {
  const _BottomActionBar({
    required this.hasSelection,
    required this.onPrint,
    required this.onEdit,
    required this.onMarkSold,
    required this.onWriteOff,
  });

  final bool hasSelection;
  final VoidCallback onPrint;
  final VoidCallback onEdit;
  final VoidCallback onMarkSold;
  final VoidCallback onWriteOff;

  static const _soldGreen = Color(0xFF1B5E20);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: hasSelection ? onPrint : null,
              icon: const Icon(Icons.print_outlined),
              label: const Text('Распечатать дубликат бирки'),
            ),
            OutlinedButton.icon(
              onPressed: hasSelection ? onEdit : null,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Редактировать карточку'),
            ),
            FilledButton.icon(
              onPressed: hasSelection ? onMarkSold : null,
              icon: const Icon(Icons.handshake_outlined),
              label: const Text('Продано'),
              style: FilledButton.styleFrom(
                backgroundColor: _soldGreen,
                foregroundColor: Colors.white,
              ),
            ),
            OutlinedButton.icon(
              onPressed: hasSelection ? onWriteOff : null,
              icon: const Icon(Icons.remove_shopping_cart_outlined),
              label: const Text('Списать / Изъять с витрины'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.saleRed,
                side: const BorderSide(color: AppColors.saleRed),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManualProductDialog extends StatefulWidget {
  const _ManualProductDialog({
    required this.database,
    required this.onSaved,
    this.editProduct,
  });

  final DatabaseService database;
  final Future<void> Function({required bool asDraft}) onSaved;
  final Map<String, dynamic>? editProduct;

  bool get isEditMode => editProduct != null;

  @override
  State<_ManualProductDialog> createState() => _ManualProductDialogState();
}

class _ManualProductDialogState extends State<_ManualProductDialog> {
  static const _nameCategories = [
    'Кольцо',
    'Серьги',
    'Цепь',
    'Браслет',
    'Другое',
  ];

  static const _manufacturerOptions = [
    'Sokolov',
    'Диамант',
    'DINASTIA',
    'new gold',
    'Ганибал',
    'Елена',
    'BEST',
    'caravan',
    'SOFIZAR',
    'UZ GOLD',
    'volkov',
    'Виноградов',
    'Высоковы',
    'Гиалит',
    'Диана',
    'Макс',
    'ОАЗИС',
    'Другое',
  ];

  final _skuController = TextEditingController();
  final _customNameController = TextEditingController();
  final _customManufacturerController = TextEditingController();
  final _weightController = TextEditingController();
  final _sizeController = TextEditingController();
  final _priceController = TextEditingController();
  final _gemController = TextEditingController();
  final _notesController = TextEditingController();

  String _productTypeCategory = _nameCategories.first;
  String _manufacturerCategory = _manufacturerOptions.first;
  String _metalCategory = 'gold';
  String _goldType = '585 красное';
  String _silverType = '925 Родированное';
  bool _saving = false;

  List<String> _imageUrls = [];
  final List<XFile> _deferredPhotos = [];

  static const _goldTypes = [
    '585 красное',
    '585 жёлтое',
    '585 белое',
    '750 жёлтое',
    '750 белое',
  ];

  static const _silverTypes = [
    '925 Родированное',
    '925 Позолоченное',
    '925 Комбинированное',
    '925 чернение',
  ];

  bool get _isEditMode => widget.isEditMode;

  int get _totalPhotoCount => _imageUrls.length + _deferredPhotos.length;

  String get _resolvedMetalType =>
      _metalCategory == 'gold' ? _goldType : _silverType;

  String get _resolvedProductName {
    if (_productTypeCategory == 'Другое') {
      return _customNameController.text.trim();
    }
    return _productTypeCategory;
  }

  String get _resolvedManufacturer {
    if (_manufacturerCategory == 'Другое') {
      return _customManufacturerController.text.trim();
    }
    return _manufacturerCategory;
  }

  List<String> get _metalDropdownOptions {
    final base = _metalCategory == 'gold'
        ? List<String>.from(_goldTypes)
        : List<String>.from(_silverTypes);
    final current = _resolvedMetalType;
    if (current.isNotEmpty && !base.contains(current)) {
      base.insert(0, current);
    }
    return base;
  }

  @override
  void initState() {
    super.initState();
    final edit = widget.editProduct;
    if (edit == null) return;

    _skuController.text = edit['sku']?.toString().trim() ?? '';
    _weightController.text = _formatNumField(edit['weight_grams']);
    _sizeController.text = _formatNumField(edit['size_value']);
    _gemController.text =
        (edit['gem_inserts'] ?? edit['insert'])?.toString().trim() ?? '';
    _notesController.text = edit['notes']?.toString().trim() ?? '';
    _initPriceField(edit);
    _applyMetalFromStored(
      (edit['metal_type'] ?? edit['metal'])?.toString() ?? '',
    );
    _imageUrls = List<String>.from(productGalleryImageUrls(edit));
    _initNameFields(_extractStoredName(edit));
    _initManufacturerFields(edit['manufacturer']?.toString().trim() ?? '');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_hydrateGalleryFromServer());
    });
  }

  Future<void> _hydrateGalleryFromServer() async {
    if (!_isEditMode) return;
    final sku = _skuController.text.trim();
    if (sku.isEmpty) return;
    try {
      final media = await widget.database.fetchProductMediaFieldsBySku(sku);
      if (!mounted || media == null) return;
      final merged = Map<String, dynamic>.from(widget.editProduct!)
        ..addAll(media);
      final urls = productGalleryImageUrls(merged);
      if (urls.isEmpty) return;
      setState(() => _imageUrls = List<String>.from(urls));
    } catch (error, stackTrace) {
      debugPrint('_ManualProductDialog._hydrateGalleryFromServer: $error');
      debugPrint('$stackTrace');
    }
  }

  void _initManufacturerFields(String storedManufacturer) {
    if (storedManufacturer.isEmpty) return;
    if (_manufacturerOptions.contains(storedManufacturer)) {
      _manufacturerCategory = storedManufacturer;
      return;
    }
    _manufacturerCategory = 'Другое';
    _customManufacturerController.text = storedManufacturer;
  }

  void _initPriceField(Map<String, dynamic> row) {
    final raw = row['price'] ?? row['sale_price'];
    if (raw == null) return;
    if (raw is num) {
      final value = raw.toInt();
      if (value > 0) {
        _priceController.text = '$value';
      }
      return;
    }
    final text = raw.toString().trim();
    if (text.isNotEmpty) {
      _priceController.text = text;
    }
  }

  void _initNameFields(String storedName) {
    if (storedName.isEmpty) return;
    if (_nameCategories.contains(storedName)) {
      _productTypeCategory = storedName;
      return;
    }
    _productTypeCategory = 'Другое';
    _customNameController.text = storedName;
  }

  static String _extractStoredName(Map<String, dynamic> row) {
    final raw = row['name'];
    if (raw is String) return raw.trim();
    if (raw is Map) {
      for (final key in ['ru', 'ko', 'en']) {
        final text = raw[key]?.toString().trim();
        if (text != null && text.isNotEmpty) return text;
      }
    }
    return '';
  }

  Future<void> _confirmRemoveNetworkPhoto(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить фото?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.saleRed,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (index < 0 || index >= _imageUrls.length) return;
    setState(() => _imageUrls = List<String>.from(_imageUrls)..removeAt(index));
  }

  Future<void> _confirmRemoveDeferredPhoto(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить фото?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.saleRed,
            ),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (index < 0 || index >= _deferredPhotos.length) return;
    setState(() => _deferredPhotos.removeAt(index));
  }

  @override
  void dispose() {
    _skuController.dispose();
    _customNameController.dispose();
    _customManufacturerController.dispose();
    _weightController.dispose();
    _sizeController.dispose();
    _priceController.dispose();
    _gemController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  static String _formatNumField(Object? value) {
    if (value == null) return '';
    if (value is num) {
      final d = value.toDouble();
      if (d == d.roundToDouble()) return '${d.toInt()}';
      return d.toStringAsFixed(2);
    }
    return value.toString().trim();
  }

  void _applyMetalFromStored(String metalType) {
    final stored = metalType.trim();
    if (stored.isEmpty) return;

    final lower = stored.toLowerCase();
    final isSilver = lower.contains('сереб') ||
        lower.contains('925') ||
        _silverTypes.any((probe) => lower.contains(probe.toLowerCase()));

    if (isSilver) {
      _metalCategory = 'silver';
      _silverType = _silverTypes.firstWhere(
        (probe) => stored == probe || stored.contains(probe),
        orElse: () => _silverTypes.first,
      );
    } else {
      _metalCategory = 'gold';
      _goldType = _goldTypes.firstWhere(
        (item) => stored == item,
        orElse: () => _goldTypes.firstWhere(
          (item) => stored.contains(item.split(' ').first),
          orElse: () => stored,
        ),
      );
      if (!_goldTypes.contains(_goldType)) {
        _goldType = _goldTypes.first;
      }
    }
  }

  void _applyProbe585() {
    setState(() {
      _metalCategory = 'gold';
      _goldType = '585 красное';
    });
  }

  void _applyProbe925() {
    setState(() {
      _metalCategory = 'silver';
      _silverType = '925 Родированное';
    });
  }

  Future<void> _pickPhoto() async {
    if (_totalPhotoCount >= ProductItem.maxGalleryImages) {
      _snack('Лимит ${ProductItem.maxGalleryImages} фото', error: true);
      return;
    }

    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 88,
    );
    if (picked == null || !mounted) return;

    setState(() => _deferredPhotos.add(picked));
  }

  Future<void> _uploadDeferredPhotos(String sku) async {
    for (final file in _deferredPhotos) {
      final bytes = await file.readAsBytes();
      final url = await widget.database.uploadProductAdditionalImage(
        sku: sku,
        bytes: bytes,
        contentType: file.mimeType ?? 'image/jpeg',
      );
      if (url == null) {
        throw StateError('Не удалось загрузить ${file.name}');
      }
    }
  }

  static int? _restockQuantityIfMissing(Map<String, dynamic> row) {
    final status = row['status']?.toString().trim();
    if (status == 'hidden') return null;

    final raw = row['stock_quantity'];
    if (raw == null) return 1;
    if (raw is num) {
      return raw.toInt() <= 0 ? 1 : null;
    }
    final parsed = int.tryParse(raw.toString().trim());
    if (parsed == null) return 1;
    return parsed <= 0 ? 1 : null;
  }

  Future<void> _submit({required bool asDraft}) async {
    final sku = _skuController.text.trim();
    final weight = double.tryParse(_weightController.text.replaceAll(',', '.'));
    final productName = _resolvedProductName;

    if (productName.isEmpty) {
      _snack('Укажите наименование изделия', error: true);
      return;
    }
    if (sku.isEmpty || weight == null || weight <= 0) {
      _snack('Укажите SKU и вес (г)', error: true);
      return;
    }
    final price = int.tryParse(_priceController.text.replaceAll(RegExp(r'[^\d]'), ''));
    if (price == null || price <= 0) {
      _snack('Укажите цену продажи (₩) больше 0', error: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final size = double.tryParse(_sizeController.text.replaceAll(',', '.'));
      final notes = _notesController.text.trim();
      final manufacturer = _resolvedManufacturer;

      final ok = _isEditMode
          ? await widget.database.updateManualProduct(
              productId: widget.editProduct!['id']?.toString() ?? '',
              sku: sku,
              name: productName,
              metalType: _resolvedMetalType,
              weightGrams: weight,
              price: price,
              sizeValue: size,
              gemInserts: _gemController.text,
              notes: notes,
              manufacturer: manufacturer,
              stockQuantity: _restockQuantityIfMissing(widget.editProduct!),
            )
          : await widget.database.insertManualProduct(
              sku: sku,
              name: productName,
              metalType: _resolvedMetalType,
              weightGrams: weight,
              price: price,
              sizeValue: size,
              gemInserts: _gemController.text,
              notes: notes,
              isDraft: asDraft,
              manufacturer: manufacturer,
            );

      if (!ok) {
        _snack(
          _isEditMode
              ? 'Не удалось обновить карточку'
              : (asDraft
                  ? 'Не удалось сохранить в черновики'
                  : 'Не удалось добавить товар'),
          error: true,
        );
        return;
      }

      if (_isEditMode) {
        final productId = widget.editProduct!['id']?.toString().trim() ?? '';
        final galleryOk = await widget.database.updateProductGalleryByProductId(
          productId: productId,
          additionalImages: _imageUrls,
        );
        if (!galleryOk) {
          _snack('Карточка сохранена, но галерея фото не обновилась', error: true);
        }
      }

      if (_deferredPhotos.isNotEmpty) {
        await _uploadDeferredPhotos(sku);
      }

      await widget.onSaved(asDraft: asDraft);
      if (!mounted) return;
      Navigator.pop(context);
    } catch (error) {
      _snack('Ошибка: $error', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? AppColors.saleRed : AppColors.primary,
      ),
    );
  }

  Widget _buildManualPhotoGrid() {
    return GridView.count(
      crossAxisCount: 2,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
      childAspectRatio: 1,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: List.generate(ProductItem.maxGalleryImages, (index) {
        if (index < _imageUrls.length) {
          return _ManualDialogPhotoSlot(
            url: _imageUrls[index],
            onRemove: () => _confirmRemoveNetworkPhoto(index),
          );
        }
        final deferredIndex = index - _imageUrls.length;
        if (deferredIndex < _deferredPhotos.length) {
          return _ManualDialogPhotoSlot(
            deferredFile: _deferredPhotos[deferredIndex],
            onRemove: () => _confirmRemoveDeferredPhoto(deferredIndex),
          );
        }
        return const _ManualDialogPhotoSlot();
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        _isEditMode ? 'Редактировать карточку' : 'Добавить товар',
        style: AppTypography.heading(fontSize: 18),
      ),
      content: SizedBox(
        width: 520,
        child: Scrollbar(
          thumbVisibility: true,
          child: SingleChildScrollView(
            primary: false,
            padding: const EdgeInsets.only(top: 4, right: 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                spacing: 8,
                children: [
                  ActionChip(
                    label: const Text('Проба 585'),
                    onPressed: _applyProbe585,
                  ),
                  ActionChip(
                    label: const Text('Проба 925'),
                    onPressed: _applyProbe925,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'gold', label: Text('Золото')),
                  ButtonSegment(value: 'silver', label: Text('Серебро')),
                ],
                selected: {_metalCategory},
                onSelectionChanged: (value) {
                  setState(() => _metalCategory = value.first);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _metalCategory == 'gold' ? _goldType : _silverType,
                decoration: const InputDecoration(
                  labelText: 'Тип металла',
                  border: OutlineInputBorder(),
                ),
                items: _metalDropdownOptions
                    .map(
                      (item) => DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    if (_metalCategory == 'gold') {
                      _goldType = value;
                    } else {
                      _silverType = value;
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _manufacturerCategory,
                decoration: const InputDecoration(
                  labelText: 'Производитель',
                  border: OutlineInputBorder(),
                ),
                items: _manufacturerOptions
                    .map(
                      (item) => DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _manufacturerCategory = value);
                },
              ),
              if (_manufacturerCategory == 'Другое') ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _customManufacturerController,
                  decoration: const InputDecoration(
                    labelText: 'Своё наименование производителя',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _productTypeCategory,
                decoration: const InputDecoration(
                  labelText: 'Категория изделия',
                  border: OutlineInputBorder(),
                ),
                items: _nameCategories
                    .map(
                      (item) => DropdownMenuItem(value: item, child: Text(item)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _productTypeCategory = value);
                },
              ),
              if (_productTypeCategory == 'Другое') ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _customNameController,
                  decoration: const InputDecoration(
                    labelText: 'Своё наименование',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _skuController,
                readOnly: _isEditMode,
                decoration: InputDecoration(
                  labelText: 'SKU / артикул',
                  border: const OutlineInputBorder(),
                  filled: _isEditMode,
                  helperText: _isEditMode ? 'SKU нельзя менять (ключ карточки)' : null,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _weightController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Вес, г',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _sizeController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Размер',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _gemController,
                decoration: const InputDecoration(
                  labelText: 'Вставки',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _priceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Цена продажи (₩)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Фото (до ${ProductItem.maxGalleryImages})',
                style: AppTypography.heading(fontSize: 15),
              ),
              const SizedBox(height: 8),
              _buildManualPhotoGrid(),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _saving ? null : _pickPhoto,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: Text(
                  'Добавить фото ($_totalPhotoCount/${ProductItem.maxGalleryImages})',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _notesController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Описание (notes)',
                  border: OutlineInputBorder(),
                  helperText: 'Заметки администратора; наименование — в категории выше',
                ),
              ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Закрыть'),
        ),
        if (!_isEditMode)
          OutlinedButton(
            onPressed: _saving ? null : () => _submit(asDraft: true),
            child: Text(_saving ? 'Сохранение…' : 'Сохранить в черновики'),
          ),
        FilledButton(
          onPressed: _saving ? null : () => _submit(asDraft: false),
          child: Text(
            _saving
                ? 'Сохранение…'
                : (_isEditMode ? 'Сохранить' : 'Добавить на витрину'),
          ),
        ),
      ],
    );
  }
}

class _ManualDialogPhotoSlot extends StatelessWidget {
  const _ManualDialogPhotoSlot({
    this.url,
    this.deferredFile,
    this.onRemove,
  });

  final String? url;
  final XFile? deferredFile;
  final VoidCallback? onRemove;

  bool get _hasPhoto =>
      (url != null && url!.isNotEmpty) || deferredFile != null;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.cardBackground,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: !_hasPhoto
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.image_not_supported_outlined,
                          color: AppColors.textSecondary.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 4),
                        Text('Нет фото', style: AppTypography.productMeta()),
                      ],
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: url != null && url!.isNotEmpty
                          ? Image.network(
                              url!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  const Icon(Icons.broken_image_outlined),
                            )
                          : _DeferredPhotoPreview(file: deferredFile!),
                    ),
            ),
          ),
          if (_hasPhoto && onRemove != null)
            Positioned(
              top: 6,
              right: 6,
              child: Material(
                color: AppColors.saleRed,
                elevation: 2,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onRemove,
                  customBorder: const CircleBorder(),
                  child: const SizedBox(
                    width: 28,
                    height: 28,
                    child: Icon(
                      Icons.close,
                      size: 18,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DeferredPhotoPreview extends StatelessWidget {
  const _DeferredPhotoPreview({required this.file});

  final XFile file;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: file.readAsBytes(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        }
        return Image.memory(
          snapshot.data!,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
        );
      },
    );
  }
}
