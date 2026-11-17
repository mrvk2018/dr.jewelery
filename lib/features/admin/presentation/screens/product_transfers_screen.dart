import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/services/database_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/store_location_utils.dart';

/// Трансферы изделий между ICN и ANS (RPC 043).
class ProductTransfersScreen extends StatefulWidget {
  ProductTransfersScreen({
    super.key,
    required this.actorCode,
    DatabaseService? database,
  }) : database = database ?? DatabaseService.create();

  final String actorCode;
  final DatabaseService database;

  @override
  State<ProductTransfersScreen> createState() => _ProductTransfersScreenState();
}

class _ProductTransfersScreenState extends State<ProductTransfersScreen> {
  static const _openStatuses = {
    'in_transit',
    'pending',
    'sent',
    'в пути',
  };

  String _statusFilter = 'in_transit';
  String? _directionFilter;
  final _searchController = TextEditingController();

  List<Map<String, dynamic>> _allRows = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final statusArg = _statusFilter == 'all' ? null : _statusFilter;
      final rows = await widget.database.listProductTransfers(
        status: statusArg,
        store: _directionFilter,
      );
      if (!mounted) return;
      setState(() => _allRows = rows);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _visibleRows {
    final q = _searchController.text.trim().toLowerCase();
    final weightQuery = double.tryParse(
      q.replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.]'), ''),
    );

    return _allRows.where((row) {
      if (_directionFilter == 'TO_ANS' &&
          row['to_store']?.toString().toUpperCase() != 'ANS') {
        return false;
      }
      if (_directionFilter == 'TO_ICN' &&
          row['to_store']?.toString().toUpperCase() != 'ICN') {
        return false;
      }
      if (q.isEmpty) return true;
      final sku = row['sku']?.toString().toLowerCase() ?? '';
      if (sku.contains(q)) return true;
      if (weightQuery != null) {
        final w = (row['weight_grams'] as num?)?.toDouble();
        if (w != null && w == weightQuery) return true;
      }
      return false;
    }).toList();
  }

  static bool _isOpenStatus(String? status) {
    final raw = status?.trim() ?? '';
    if (raw.isEmpty) return false;
    if (_openStatuses.contains(raw.toLowerCase()) || raw == 'В пути') {
      return true;
    }
    return raw.toLowerCase() == 'in_transit';
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

  Future<void> _completeTransfer(Map<String, dynamic> row) async {
    final id = row['id']?.toString() ?? '';
    if (id.isEmpty) return;
    setState(() => _busy = true);
    try {
      final result = await widget.database.completeProductTransferById(
        transferId: id,
        receiverCode: widget.actorCode,
      );
      if (!mounted) return;
      if (result['ok'] != true) {
        _snack(result['error']?.toString() ?? 'Приём не выполнен', error: true);
        return;
      }
      final alert = result['alert']?.toString();
      _snack('Трансфер принят${alert != null ? ' · $alert' : ''}');
      await _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelTransfer(Map<String, dynamic> row) async {
    final id = row['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final sku = row['sku']?.toString() ?? '—';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отменить трансфер?'),
        content: Text('SKU $sku вернётся в магазин-отправитель.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Отменить')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final result = await widget.database.cancelProductTransferById(
        transferId: id,
        actorCode: widget.actorCode,
      );
      if (!mounted) return;
      if (result['ok'] != true) {
        _snack(result['error']?.toString() ?? 'Отмена не выполнена', error: true);
        return;
      }
      _snack('Трансфер отменён');
      await _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _formatWhen(Object? raw) {
    if (raw == null) return '—';
    final text = raw.toString();
    final dt = DateTime.tryParse(text);
    if (dt == null) return text;
    return DateFormat('dd.MM.yy HH:mm').format(dt.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final rows = _visibleRows;

    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _FiltersBar(
                statusFilter: _statusFilter,
                directionFilter: _directionFilter,
                searchController: _searchController,
                onStatusChanged: (v) {
                  setState(() => _statusFilter = v);
                  _reload();
                },
                onDirectionChanged: (v) => setState(() => _directionFilter = v),
                onSearchChanged: () => setState(() {}),
                onRefresh: _reload,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: AppTypography.caption(color: AppColors.saleRed)),
              ],
              const SizedBox(height: 12),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : rows.isEmpty
                        ? Center(
                            child: Text(
                              'Нет трансферов по фильтру',
                              style: AppTypography.productMeta(),
                            ),
                          )
                        : ListView.builder(
                            itemCount: rows.length,
                            itemBuilder: (context, index) {
                              return _TransferCard(
                                row: rows[index],
                                busy: _busy,
                                isOpen: _isOpenStatus(rows[index]['status']?.toString()),
                                formatWhen: _formatWhen,
                                onComplete: () => _completeTransfer(rows[index]),
                                onCancel: () => _cancelTransfer(rows[index]),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
        if (_busy)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(minHeight: 2),
          ),
      ],
    );
  }
}

class _FiltersBar extends StatelessWidget {
  const _FiltersBar({
    required this.statusFilter,
    required this.directionFilter,
    required this.searchController,
    required this.onStatusChanged,
    required this.onDirectionChanged,
    required this.onSearchChanged,
    required this.onRefresh,
  });

  final String statusFilter;
  final String? directionFilter;
  final TextEditingController searchController;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String?> onDirectionChanged;
  final VoidCallback onSearchChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('Статус:', style: AppTypography.caption()),
                for (final (value, label) in const [
                  ('in_transit', 'В пути'),
                  ('completed', 'Завершённые'),
                  ('cancelled', 'Отменённые'),
                  ('all', 'Все'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: statusFilter == value,
                    onSelected: (_) => onStatusChanged(value),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Text('Направление:', style: AppTypography.caption()),
                for (final (value, label) in const [
                  (null, 'Все'),
                  ('TO_ANS', '→ Ансан'),
                  ('TO_ICN', '→ Инчхон'),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: directionFilter == value,
                    onSelected: (_) => onDirectionChanged(value),
                  ),
                IconButton(
                  tooltip: 'Обновить',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: searchController,
              onChanged: (_) => onSearchChanged(),
              decoration: const InputDecoration(
                labelText: 'SKU или вес (г)',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransferCard extends StatelessWidget {
  const _TransferCard({
    required this.row,
    required this.busy,
    required this.isOpen,
    required this.formatWhen,
    required this.onComplete,
    required this.onCancel,
  });

  final Map<String, dynamic> row;
  final bool busy;
  final bool isOpen;
  final String Function(Object? raw) formatWhen;
  final VoidCallback onComplete;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final sku = row['sku']?.toString() ?? '—';
    final from = row['from_store']?.toString() ?? '—';
    final to = row['to_store']?.toString() ?? '—';
    final status = row['status']?.toString() ?? '—';
    final sender = row['sender_code']?.toString() ?? '—';
    final metal = row['metal_type']?.toString() ?? '—';
    final weight = (row['weight_grams'] as num?)?.toDouble();
    final notes = row['notes']?.toString().trim() ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    sku,
                    style: AppTypography.heading(fontSize: 16),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.border.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(status, style: AppTypography.caption()),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$metal · ${weight != null ? '${weight.toStringAsFixed(2)} г' : '—'}',
              style: AppTypography.productMeta(),
            ),
            Text(
              '${storeLocationDisplayLabel(from)} → ${storeLocationDisplayLabel(to)}',
              style: AppTypography.productMeta().copyWith(fontWeight: FontWeight.w600),
            ),
            Text('Отправил: $sender · ${formatWhen(row['created_at'])}',
                style: AppTypography.productMeta()),
            if (notes.isNotEmpty)
              Text('Комментарий: $notes', style: AppTypography.productMeta()),
            if (isOpen) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton(
                    onPressed: busy ? null : onComplete,
                    child: const Text('Принять в магазин'),
                  ),
                  OutlinedButton(
                    onPressed: busy ? null : onCancel,
                    child: const Text('Отменить'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}