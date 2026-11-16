import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/services/database_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/won_format.dart';
import '../../../printing/domain/jewelry_label_data.dart';
import '../../../printing/presentation/widgets/jewelry_label_preview.dart';
import '../../../printing/presentation/widgets/jewelry_label_print_dialog.dart';

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

  /// Как витрина админки: `sale_price`, затем legacy `price` (KRW).
  static int? _salePriceKrw(Map<String, dynamic> row) {
    final raw = row['sale_price'] ?? row['price'];
    if (raw is num) {
      final value = raw.round();
      return value > 0 ? value : null;
    }
    if (raw == null) return null;
    final parsed = int.tryParse(raw.toString().replaceAll(RegExp(r'[^\d]'), ''));
    if (parsed == null || parsed <= 0) return null;
    return parsed;
  }

  static Widget _priceCell(Map<String, dynamic> row) {
    final krw = _salePriceKrw(row);
    if (krw == null) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Text(
          '—',
          maxLines: 1,
          style: AppTypography.productMeta().copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      );
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Text(
        formatWon(krw),
        maxLines: 1,
        style: AppTypography.price(fontSize: 13),
      ),
    );
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

  void _safeFireAndForgetPrint(Map<String, dynamic> productRow) {
    Future.microtask(() async {
      try {
        await _printLabelForProduct(productRow, userFeedback: false);
      } catch (error, stackTrace) {
        debugPrint('Тихая ошибка печати в песочнице: $error');
        debugPrint('$stackTrace');
      }
    });
  }

  Future<void> _printLabelForProduct(
    Map<String, dynamic> row, {
    bool userFeedback = true,
  }) async {
    try {
      await JewelryLabelPrintDialog.showAndPrint(
        context,
        productRow: row,
        titleSuffix: 'Приёмка',
      );
      if (userFeedback && mounted) {
        _showSnack('Печать ценника запущена');
      }
    } catch (error, stackTrace) {
      debugPrint('DraftIntakeScreen._printLabelForProduct failed: $error');
      debugPrint('$stackTrace');
      if (userFeedback && mounted) {
        _showSnack('Ошибка печати: $error', isError: true);
      }
      rethrow;
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
      _showSnack('Принят $sku — на витрине (stock=1)');
      if (mounted) setState(() => _rowBusySkus.remove(sku));
      _safeFireAndForgetPrint(printRow);
      await _runSearch(_searchController.text);
    } catch (error) {
      if (!mounted) return;
      _showSnack('Ошибка приёмки: $error', isError: true);
    } finally {
      if (mounted) setState(() => _rowBusySkus.remove(sku));
    }
  }

  Future<void> _deleteSingle(Map<String, dynamic> row) async {
    final sku = _field(row, 'sku');
    if (sku == '—') return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Удалить черновик?', style: AppTypography.heading(fontSize: 18)),
        content: Text(
          'SKU $sku будет удалён из базы без возможности восстановления.',
          style: AppTypography.productMeta(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.saleRed),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final productId = row['id']?.toString().trim();
    setState(() => _rowBusySkus.add(sku));
    try {
      final res = await widget.database.deleteDraftProduct(
        id: productId != null && productId.isNotEmpty ? productId : null,
        sku: sku,
      );
      if (!mounted) return;
      if (!res.ok) {
        _showSnack(
          'Не удалось удалить $sku: ${res.error ?? 'неизвестная ошибка'}',
          isError: true,
        );
        return;
      }
      setState(() {
        _drafts = _drafts.where((draft) {
          final draftId = draft['id']?.toString().trim();
          if (productId != null && productId.isNotEmpty && draftId != null) {
            return draftId != productId;
          }
          return _field(draft, 'sku') != sku;
        }).toList(growable: false);
      });
      _showSnack('Черновик $sku удалён');
      await _runSearch(_searchController.text);
    } catch (error) {
      if (!mounted) return;
      _showSnack('Ошибка удаления: $error', isError: true);
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
        _safeFireAndForgetPrint(row);
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
                    onPrintRow: _printLabelForProduct,
                    onDeleteRow: _deleteSingle,
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

abstract final class _DraftTableLayout {
  static const narrowBreakpoint = 680.0;
  static const photoSize = 40.0;
  static const actionsWidth = 132.0;
  static const horizontalPadding = 12.0;
  static const rowVerticalPadding = 10.0;
}

class _DraftTable extends StatelessWidget {
  const _DraftTable({
    required this.drafts,
    required this.loading,
    required this.busySkus,
    required this.onAcceptRow,
    required this.onPrintRow,
    required this.onDeleteRow,
  });

  final List<Map<String, dynamic>> drafts;
  final bool loading;
  final Set<String> busySkus;
  final Future<void> Function(Map<String, dynamic> row) onAcceptRow;
  final Future<void> Function(Map<String, dynamic> row) onPrintRow;
  final Future<void> Function(Map<String, dynamic> row) onDeleteRow;

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
          final narrow = constraints.maxWidth < _DraftTableLayout.narrowBreakpoint;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _DraftTableHeader(narrow: narrow),
              const Divider(height: 1, color: AppColors.border),
              Expanded(
                child: ListView.separated(
                  itemCount: drafts.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, color: AppColors.border),
                  itemBuilder: (context, index) {
                    final row = drafts[index];
                    final sku = _DraftIntakeScreenState._field(row, 'sku');
                    final busy = busySkus.contains(sku);
                    return narrow
                        ? _DraftTableNarrowRow(
                            row: row,
                            sku: sku,
                            busy: busy,
                            onAccept: () => onAcceptRow(row),
                            onPrint: () => onPrintRow(row),
                            onDelete: () => onDeleteRow(row),
                          )
                        : _DraftTableWideRow(
                            row: row,
                            sku: sku,
                            busy: busy,
                            onAccept: () => onAcceptRow(row),
                            onPrint: () => onPrintRow(row),
                            onDelete: () => onDeleteRow(row),
                          );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DraftTableHeader extends StatelessWidget {
  const _DraftTableHeader({required this.narrow});

  final bool narrow;

  static TextStyle get _labelStyle =>
      AppTypography.caption(fontWeight: FontWeight.w700);

  @override
  Widget build(BuildContext context) {
    final pad = const EdgeInsets.symmetric(
      horizontal: _DraftTableLayout.horizontalPadding,
      vertical: _DraftTableLayout.rowVerticalPadding,
    );
    if (narrow) {
      return Container(
        color: AppColors.cardBackground,
        padding: pad,
        child: Text('Черновики', style: _labelStyle),
      );
    }
    return Container(
      color: AppColors.cardBackground,
      padding: pad,
      child: Row(
        children: [
          const SizedBox(width: _DraftTableLayout.photoSize),
          const SizedBox(width: 8),
          const Expanded(flex: 3, child: _DraftHeaderCell('SKU')),
          const Expanded(flex: 2, child: _DraftHeaderCell('Металл')),
          const Expanded(flex: 1, child: _DraftHeaderCell('Вес, г')),
          const Expanded(flex: 1, child: _DraftHeaderCell('Размер')),
          const Expanded(flex: 2, child: _DraftHeaderCell('Вставки')),
          const Expanded(flex: 2, child: _DraftHeaderCell('Цена', alignEnd: true)),
          SizedBox(
            width: _DraftTableLayout.actionsWidth,
            child: Text('Действие', style: _labelStyle, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

class _DraftHeaderCell extends StatelessWidget {
  const _DraftHeaderCell(this.label, {this.alignEnd = false});

  final String label;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: alignEnd ? TextAlign.end : TextAlign.start,
      style: _DraftTableHeader._labelStyle,
    );
  }
}

class _DraftTableWideRow extends StatelessWidget {
  const _DraftTableWideRow({
    required this.row,
    required this.sku,
    required this.busy,
    required this.onAccept,
    required this.onPrint,
    required this.onDelete,
  });

  final Map<String, dynamic> row;
  final String sku;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onPrint;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _DraftTableLayout.horizontalPadding,
        vertical: _DraftTableLayout.rowVerticalPadding,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _DraftThumbnail(
            url: _DraftIntakeScreenState._thumbnailUrl(row),
            size: _DraftTableLayout.photoSize,
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: _DraftEllipsisText(
              _DraftIntakeScreenState._field(row, 'sku'),
              style: AppTypography.caption(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            flex: 2,
            child: _DraftEllipsisText(
              _DraftIntakeScreenState._field(row, 'metal_type'),
            ),
          ),
          Expanded(
            flex: 1,
            child: _DraftFittedText(
              _DraftIntakeScreenState._weight(row).toStringAsFixed(2),
            ),
          ),
          Expanded(
            flex: 1,
            child: _DraftFittedText(
              _DraftIntakeScreenState._size(row).toStringAsFixed(2),
            ),
          ),
          Expanded(
            flex: 2,
            child: _DraftEllipsisText(
              _DraftIntakeScreenState._field(row, 'gem_inserts'),
            ),
          ),
          Expanded(
            flex: 2,
            child: Align(
              alignment: Alignment.centerRight,
              child: _DraftIntakeScreenState._priceCell(row),
            ),
          ),
          SizedBox(
            width: _DraftTableLayout.actionsWidth,
            child: _DraftRowActions(
              busy: busy,
              onAccept: onAccept,
              onPrint: onPrint,
              onDelete: onDelete,
            ),
          ),
        ],
      ),
    );
  }
}

class _DraftTableNarrowRow extends StatelessWidget {
  const _DraftTableNarrowRow({
    required this.row,
    required this.sku,
    required this.busy,
    required this.onAccept,
    required this.onPrint,
    required this.onDelete,
  });

  final Map<String, dynamic> row;
  final String sku;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onPrint;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final metaStyle = AppTypography.productMeta();
    final weight = _DraftIntakeScreenState._weight(row).toStringAsFixed(2);
    final size = _DraftIntakeScreenState._size(row).toStringAsFixed(2);
    final metal = _DraftIntakeScreenState._field(row, 'metal_type');
    final inserts = _DraftIntakeScreenState._field(row, 'gem_inserts');

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: _DraftTableLayout.horizontalPadding,
        vertical: _DraftTableLayout.rowVerticalPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _DraftThumbnail(
                url: _DraftIntakeScreenState._thumbnailUrl(row),
                size: _DraftTableLayout.photoSize,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _DraftEllipsisText(
                  sku,
                  style: AppTypography.caption(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 6),
              Flexible(child: _DraftIntakeScreenState._priceCell(row)),
              const SizedBox(width: 4),
              _DraftRowActions(
                busy: busy,
                onAccept: onAccept,
                onPrint: onPrint,
                onDelete: onDelete,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _DraftEllipsisText(
                  '$metal · $weight г · р. $size · $inserts',
                  style: metaStyle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DraftEllipsisText extends StatelessWidget {
  const _DraftEllipsisText(this.text, {this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style ?? AppTypography.productMeta(),
    );
  }
}

class _DraftFittedText extends StatelessWidget {
  const _DraftFittedText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        maxLines: 1,
        style: AppTypography.productMeta(),
      ),
    );
  }
}

class _DraftRowActions extends StatelessWidget {
  const _DraftRowActions({
    required this.busy,
    required this.onAccept,
    required this.onPrint,
    required this.onDelete,
    this.compact = false,
  });

  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onPrint;
  final VoidCallback onDelete;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final acceptStyle = FilledButton.styleFrom(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: 4,
      ),
      minimumSize: Size(compact ? 0 : 0, 30),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
    );
    final iconConstraints = BoxConstraints(
      minWidth: compact ? 28 : 32,
      minHeight: compact ? 28 : 32,
    );

    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        FilledButton.tonal(
          onPressed: busy ? null : onAccept,
          style: acceptStyle,
          child: busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(compact ? 'Прин.' : 'Принять'),
        ),
        IconButton(
          tooltip: 'Печать ценника',
          onPressed: busy ? null : onPrint,
          padding: EdgeInsets.zero,
          constraints: iconConstraints,
          iconSize: compact ? 18 : 20,
          icon: Icon(
            Icons.print_outlined,
            color: busy ? AppColors.textSecondary : AppColors.accent,
          ),
        ),
        IconButton(
          tooltip: 'Удалить черновик',
          onPressed: busy ? null : onDelete,
          padding: EdgeInsets.zero,
          constraints: iconConstraints,
          iconSize: compact ? 18 : 20,
          icon: Icon(
            Icons.delete_outline,
            color: busy ? AppColors.textSecondary : AppColors.saleRed,
          ),
        ),
      ],
    );
  }
}

class _DraftThumbnail extends StatelessWidget {
  const _DraftThumbnail({this.url, this.size = 48});

  final String? url;
  final double size;

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
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _placeholder(),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return SizedBox(
            width: size,
            height: size,
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
      width: size,
      height: size,
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
