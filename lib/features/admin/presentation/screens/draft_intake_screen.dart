import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/services/database_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../printing/application/label_print_service.dart';
import '../../../printing/domain/jewelry_label_data.dart';
import '../../../printing/domain/jewelry_label_layout.dart';
import '../../../printing/presentation/widgets/jewelry_label_preview.dart';

/// Складская приёмка черновиков (`stock_quantity = 0` → `1`) + печать этикеток.
class DraftIntakeScreen extends StatefulWidget {
  DraftIntakeScreen({
    super.key,
    DatabaseService? database,
  }) : database = database ?? DatabaseService.create();

  final DatabaseService database;

  @override
  State<DraftIntakeScreen> createState() => _DraftIntakeScreenState();
}

class _DraftIntakeScreenState extends State<DraftIntakeScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  final LabelPrintService _labelPrintService = const LabelPrintService(
    protocol: LabelPrinterProtocol.tspl,
  );

  List<Map<String, dynamic>> _drafts = const [];
  bool _searchLoading = false;
  bool _bulkBusy = false;
  final Set<String> _rowBusySkus = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _runSearch(_searchController.text);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _runSearch(_searchController.text);
    });
  }

  Future<void> _runSearch(String query) async {
    setState(() => _searchLoading = true);
    try {
      final rows = await widget.database.searchDraftProducts(query);
      if (!mounted) return;
      setState(() => _drafts = rows);
    } catch (error) {
      if (!mounted) return;
      _showSnack('Ошибка поиска: $error', isError: true);
    } finally {
      if (mounted) setState(() => _searchLoading = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppColors.saleRed : AppColors.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  static String _field(Map<String, dynamic> row, String key) {
    final value = row[key];
    if (value == null) return '—';
    final text = value.toString().trim();
    return text.isEmpty ? '—' : text;
  }

  static double _weight(Map<String, dynamic> row) {
    return (row['weight_grams'] as num?)?.toDouble() ?? 0;
  }

  static double _size(Map<String, dynamic> row) {
    return (row['size_value'] as num?)?.toDouble() ?? 0;
  }

  static String? _thumbnailUrl(Map<String, dynamic> row) {
    final direct = row['image_url']?.toString().trim();
    if (direct != null && direct.isNotEmpty) return direct;

    final raw = row['additional_images'];
    if (raw is List && raw.isNotEmpty) {
      final first = raw.first?.toString().trim() ?? '';
      if (first.isNotEmpty) return first;
    }
    return null;
  }

  Future<String?> _confirmAcceptWithPreview(Map<String, dynamic> row) async {
    final sku = _field(row, 'sku');
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => _DraftAcceptPreviewDialog(row: row, sku: sku),
    );
  }

  Future<void> _printLabelForProduct(Map<String, dynamic> row) async {
    try {
      await _labelPrintService.printFromProductMap(row);
    } catch (error, stackTrace) {
      debugPrint('DraftIntakeScreen._printLabelForProduct failed: $error');
      debugPrint('$stackTrace');
      if (mounted) {
        _showSnack('Ошибка печати: $error', isError: true);
      }
    }
  }

  Future<void> _acceptSingle(Map<String, dynamic> row) async {
    final sku = _field(row, 'sku');
    if (sku == '—') return;

    final productName = await _confirmAcceptWithPreview(row);
    if (productName == null || !mounted) return;

    setState(() => _rowBusySkus.add(sku));
    try {
      final notesSaved = await widget.database.updateProductNotesBySku(
        sku,
        productName,
      );
      if (!mounted) return;
      if (!notesSaved) {
        _showSnack('Не удалось сохранить наименование', isError: true);
        return;
      }

      final ok = await widget.database.activateDraftProductBySku(sku);
      if (!mounted) return;
      if (!ok) {
        _showSnack('Не удалось активировать $sku (RLS или уже принят)', isError: true);
        return;
      }

      final printRow = Map<String, dynamic>.from(row)..['notes'] = productName;
      await _printLabelForProduct(printRow);

      _showSnack('Принят $sku — этикетка отправлена на печать');
      await _runSearch(_searchController.text);
    } catch (error) {
      if (!mounted) return;
      _showSnack('Ошибка приёмки: $error', isError: true);
    } finally {
      if (mounted) setState(() => _rowBusySkus.remove(sku));
    }
  }

  Future<void> _acceptEntireShipment() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Принять всю поставку?', style: AppTypography.heading(fontSize: 18)),
        content: Text(
          'Все черновики (stock_quantity = 0) будут активированы и '
          'отправлены в общий буфер печати этикеток.',
          style: AppTypography.productMeta(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Принять всё'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _bulkBusy = true);
    try {
      final snapshot = List<Map<String, dynamic>>.from(_drafts);
      final activated = await widget.database.activateAllDraftProducts();
      if (!mounted) return;

      if (activated <= 0) {
        _showSnack('Нет черновиков для активации', isError: true);
        return;
      }

      for (final row in snapshot) {
        await _printLabelForProduct(row);
      }

      _showSnack('Активировано $activated поз. — буфер печати сформирован');
      await _runSearch(_searchController.text);
    } catch (error) {
      if (!mounted) return;
      _showSnack('Ошибка массовой приёмки: $error', isError: true);
    } finally {
      if (mounted) setState(() => _bulkBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Приёмка черновиков', style: AppTypography.heading(fontSize: 20)),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width >= 1200 ? 1200 : width),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Toolbar(
                  searchController: _searchController,
                  searchLoading: _searchLoading,
                  bulkBusy: _bulkBusy,
                  onSubmitted: (value) => _runSearch(value),
                  onBulkAccept: _acceptEntireShipment,
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: _DraftTable(
                    drafts: _drafts,
                    loading: _searchLoading,
                    busySkus: _rowBusySkus,
                    onAcceptRow: _acceptSingle,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.searchController,
    required this.searchLoading,
    required this.bulkBusy,
    required this.onSubmitted,
    required this.onBulkAccept,
  });

  final TextEditingController searchController;
  final bool searchLoading;
  final bool bulkBusy;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onBulkAccept;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: AppColors.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: bulkBusy ? null : onBulkAccept,
              icon: bulkBusy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.inventory_2_outlined),
              label: const Text('Принять всю поставку (Массовая активация)'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: AppColors.textOnAccent,
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: searchController,
              onSubmitted: onSubmitted,
              decoration: InputDecoration(
                labelText: 'Артикул, вес (г) или «Au585 2.43»',
                hintText: 'Быстрый поиск среди черновиков',
                prefixIcon: searchLoading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Icon(Icons.search),
                filled: true,
                fillColor: AppColors.background,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DraftTable extends StatelessWidget {
  const _DraftTable({
    required this.drafts,
    required this.loading,
    required this.busySkus,
    required this.onAcceptRow,
  });

  final List<Map<String, dynamic>> drafts;
  final bool loading;
  final Set<String> busySkus;
  final Future<void> Function(Map<String, dynamic> row) onAcceptRow;

  @override
  Widget build(BuildContext context) {
    if (loading && drafts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (drafts.isEmpty) {
      return Center(
        child: Text(
          'Черновики не найдены',
          style: AppTypography.productMeta().copyWith(fontSize: 16),
        ),
      );
    }

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                child: SingleChildScrollView(
                  child: DataTable(
                    headingRowColor: WidgetStateProperty.all(
                      AppColors.cardBackground,
                    ),
                    columns: const [
                      DataColumn(label: Text('Фото')),
                      DataColumn(label: Text('SKU')),
                      DataColumn(label: Text('Металл')),
                      DataColumn(label: Text('Вес, г')),
                      DataColumn(label: Text('Размер')),
                      DataColumn(label: Text('Вставки')),
                      DataColumn(label: Text('Действие')),
                    ],
                    rows: drafts.map((row) {
                      final sku = _DraftIntakeScreenState._field(row, 'sku');
                      final busy = busySkus.contains(sku);
                      return DataRow(
                        cells: [
                          DataCell(
                            _DraftThumbnail(url: _DraftIntakeScreenState._thumbnailUrl(row)),
                          ),
                          DataCell(Text(sku)),
                          DataCell(
                            Text(_DraftIntakeScreenState._field(row, 'metal_type')),
                          ),
                          DataCell(
                            Text(
                              _DraftIntakeScreenState._weight(row).toStringAsFixed(2),
                            ),
                          ),
                          DataCell(
                            Text(
                              _DraftIntakeScreenState._size(row).toStringAsFixed(2),
                            ),
                          ),
                          DataCell(
                            Text(_DraftIntakeScreenState._field(row, 'gem_inserts')),
                          ),
                          DataCell(
                            FilledButton.tonal(
                              onPressed: busy ? null : () => onAcceptRow(row),
                              child: busy
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Text('Принять и напечатать'),
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
        },
      ),
    );
  }
}

class _DraftThumbnail extends StatelessWidget {
  const _DraftThumbnail({this.url});

  final String? url;

  static const _size = 48.0;

  @override
  Widget build(BuildContext context) {
    final resolved = url?.trim();
    if (resolved == null || resolved.isEmpty) {
      return _placeholder();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        resolved,
        width: _size,
        height: _size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return SizedBox(
            width: _size,
            height: _size,
            child: const Center(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      width: _size,
      height: _size,
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Icon(
        Icons.image_not_supported_outlined,
        size: 22,
        color: AppColors.textSecondary,
      ),
    );
  }
}

class _DraftAcceptPreviewDialog extends StatefulWidget {
  const _DraftAcceptPreviewDialog({
    required this.row,
    required this.sku,
  });

  final Map<String, dynamic> row;
  final String sku;

  static const _presetTypes = [
    'Кольцо',
    'Серьги',
    'Цепь',
    'Браслет',
    'Подвеска',
    'Колье',
    'Другое',
  ];

  @override
  State<_DraftAcceptPreviewDialog> createState() =>
      _DraftAcceptPreviewDialogState();
}

class _DraftAcceptPreviewDialogState extends State<_DraftAcceptPreviewDialog> {
  late String _selectedType;
  final _customNameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final existing = widget.row['notes']?.toString().trim() ?? '';
    if (existing.isNotEmpty &&
        _DraftAcceptPreviewDialog._presetTypes.contains(existing)) {
      _selectedType = existing;
    } else if (existing.isNotEmpty) {
      _selectedType = 'Другое';
      _customNameController.text = existing;
    } else {
      _selectedType = _DraftAcceptPreviewDialog._presetTypes.first;
    }
  }

  @override
  void dispose() {
    _customNameController.dispose();
    super.dispose();
  }

  String get _resolvedName {
    if (_selectedType == 'Другое') {
      return _customNameController.text.trim();
    }
    return _selectedType;
  }

  JewelryLabelData get _previewData {
    final merged = Map<String, dynamic>.from(widget.row)
      ..['notes'] = _resolvedName.isEmpty ? widget.sku : _resolvedName;
    return JewelryLabelData.fromProductMap(merged);
  }

  void _accept() {
    final name = _resolvedName;
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Укажите наименование изделия')),
      );
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Приёмка · ${widget.sku}',
        style: AppTypography.heading(fontSize: 18),
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _selectedType,
                decoration: const InputDecoration(
                  labelText: 'Наименование изделия',
                  border: OutlineInputBorder(),
                ),
                items: _DraftAcceptPreviewDialog._presetTypes
                    .map(
                      (type) => DropdownMenuItem(
                        value: type,
                        child: Text(type),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _selectedType = value);
                },
              ),
              if (_selectedType == 'Другое') ...[
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
              JewelryLabelPreview(data: _previewData),
              const SizedBox(height: 12),
              Text(
                'Наименование сохранится в notes и попадёт на бирку.',
                style: AppTypography.productMeta(),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _accept,
          child: const Text('Принять и печатать'),
        ),
      ],
    );
  }
}
