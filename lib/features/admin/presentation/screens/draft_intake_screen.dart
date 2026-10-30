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

  Future<bool> _confirmAcceptWithPreview(Map<String, dynamic> row) async {
    final labelData = JewelryLabelData.fromProductMap(row);
    final sku = _field(row, 'sku');
    final accepted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            'Приёмка · $sku',
            style: AppTypography.heading(fontSize: 18),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                JewelryLabelPreview(data: labelData),
                const SizedBox(height: 12),
                Text(
                  'Активировать stock_quantity = 1 и отправить TSPL на печать?',
                  style: AppTypography.productMeta(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Принять и печатать'),
            ),
          ],
        );
      },
    );
    return accepted == true;
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

    final confirmed = await _confirmAcceptWithPreview(row);
    if (!confirmed || !mounted) return;

    setState(() => _rowBusySkus.add(sku));
    try {
      final ok = await widget.database.activateDraftProductBySku(sku);
      if (!mounted) return;
      if (!ok) {
        _showSnack('Не удалось активировать $sku (RLS или уже принят)', isError: true);
        return;
      }

      await _printLabelForProduct(row);

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
