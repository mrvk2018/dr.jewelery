import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/database_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/product_gallery_urls.dart';
import '../../../../core/utils/store_location_utils.dart';
import '../../domain/product_transfer_item.dart';
import '../widgets/admin_product_photo_preview.dart';

/// Трансферы изделий между ICN и ANS (RPC 043/046).
class ProductTransfersScreen extends StatefulWidget {
  ProductTransfersScreen({
    super.key,
    required this.actorCode,
    this.onTransfersMutated,
    DatabaseService? database,
  }) : database = database ?? DatabaseService.create();

  final String actorCode;
  final VoidCallback? onTransfersMutated;
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

  List<ProductTransferItem> _allItems = const [];
  bool _loading = true;
  bool _busy = false;
  String? _error;
  RealtimeChannel? _realtimeChannel;

  @override
  void initState() {
    super.initState();
    _reload();
    _subscribeTransfersRealtime();
  }

  @override
  void dispose() {
    _searchController.dispose();
    final ch = _realtimeChannel;
    if (ch != null) {
      unawaited(ch.unsubscribe());
    }
    super.dispose();
  }

  void _subscribeTransfersRealtime() {
    try {
      _realtimeChannel = Supabase.instance.client
          .channel('product_transfers_screen_list')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'product_transfers',
            callback: (_) => unawaited(_reload(silent: true)),
          )
          .subscribe();
    } catch (error, stackTrace) {
      debugPrint('ProductTransfersScreen realtime: $error');
      debugPrint('$stackTrace');
    }
  }

  Future<void> _reload({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final statusArg = _statusFilter == 'all' ? null : _statusFilter;
      final rows = await widget.database.listProductTransfers(
        status: statusArg,
        store: _directionFilter,
      );
      if (!mounted) return;
      setState(() {
        _allItems = rows.map(ProductTransferItem.fromMap).toList();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted && !silent) setState(() => _loading = false);
    }
  }

  List<ProductTransferItem> get _visibleItems {
    final q = _searchController.text.trim().toLowerCase();
    final weightQuery = double.tryParse(
      q.replaceAll(',', '.').replaceAll(RegExp(r'[^0-9.]'), ''),
    );

    return _allItems.where((item) {
      final row = item.raw;
      if (_directionFilter == 'TO_ANS' &&
          item.toStore?.toUpperCase() != 'ANS') {
        return false;
      }
      if (_directionFilter == 'TO_ICN' &&
          item.toStore?.toUpperCase() != 'ICN') {
        return false;
      }
      if (q.isEmpty) return true;
      final sku = item.sku?.toLowerCase() ?? '';
      if (sku.contains(q)) return true;
      if (weightQuery != null && item.weightGrams == weightQuery) return true;
      final w = (row['weight_grams'] as num?)?.toDouble();
      if (weightQuery != null && w != null && w == weightQuery) return true;
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

  Future<void> _openPhotoPreview(ProductTransferItem item) async {
    final urls = productGalleryImageUrls(item.raw);
    final imageUrl = (item.imageUrl != null && item.imageUrl!.isNotEmpty)
        ? item.imageUrl!
        : (urls.isNotEmpty ? urls.first : null);
    if (imageUrl == null) return;

    final weight = item.weightGrams;
    final parts = <String>[
      if (item.productName != null && item.productName!.isNotEmpty)
        item.productName!,
      if (weight != null) '${weight.toStringAsFixed(2)} г',
    ];

    await showAdminProductPhotoPreview(
      context,
      title: item.sku ?? '—',
      subtitle: parts.isEmpty ? null : parts.join(' · '),
      imageUrls: [imageUrl],
    );
  }

  Future<void> _completeTransfer(ProductTransferItem item) async {
    final id = item.id ?? '';
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
      widget.onTransfersMutated?.call();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelTransfer(ProductTransferItem item) async {
    final id = item.id ?? '';
    if (id.isEmpty) return;
    final sku = item.sku ?? '—';
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
      widget.onTransfersMutated?.call();
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
    final items = _visibleItems;

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
                    : items.isEmpty
                        ? Center(
                            child: Text(
                              'Нет трансферов по фильтру',
                              style: AppTypography.productMeta(),
                            ),
                          )
                        : ListView.builder(
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final item = items[index];
                              return _TransferCard(
                                item: item,
                                busy: _busy,
                                isOpen: _isOpenStatus(item.status),
                                formatWhen: _formatWhen,
                                onPhotoTap: () => _openPhotoPreview(item),
                                onComplete: () => _completeTransfer(item),
                                onCancel: () => _cancelTransfer(item),
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

class _TransferThumbnail extends StatelessWidget {
  const _TransferThumbnail({
    required this.item,
    required this.onTap,
  });

  final ProductTransferItem item;
  final VoidCallback onTap;

  static const _size = 64.0;

  @override
  Widget build(BuildContext context) {
    final urls = productGalleryImageUrls(item.raw);
    final url = (item.imageUrl != null && item.imageUrl!.isNotEmpty)
        ? item.imageUrl
        : (urls.isNotEmpty ? urls.first : null);
    final hasPhoto = url != null && url.isNotEmpty;

    return Material(
      color: AppColors.border.withValues(alpha: 0.25),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: hasPhoto ? onTap : null,
        child: SizedBox(
          width: _size,
          height: _size,
          child: hasPhoto
              ? Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => _placeholder(),
                )
              : _placeholder(),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return const ColoredBox(
      color: Color(0xFFF0F0F0),
      child: Center(
        child: Icon(Icons.image_not_supported_outlined, color: AppColors.border),
      ),
    );
  }
}

class _TransferCard extends StatelessWidget {
  const _TransferCard({
    required this.item,
    required this.busy,
    required this.isOpen,
    required this.formatWhen,
    required this.onPhotoTap,
    required this.onComplete,
    required this.onCancel,
  });

  final ProductTransferItem item;
  final bool busy;
  final bool isOpen;
  final String Function(Object? raw) formatWhen;
  final VoidCallback onPhotoTap;
  final VoidCallback onComplete;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final sku = item.sku ?? '—';
    final from = item.fromStore ?? '—';
    final to = item.toStore ?? '—';
    final status = item.status ?? '—';
    final sender = item.senderCode ?? '—';
    final metal = item.metalType ?? '—';
    final weight = item.weightGrams;
    final notes = item.notes?.trim() ?? '';
    final name = item.productName;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TransferThumbnail(item: item, onTap: onPhotoTap),
                const SizedBox(width: 12),
                Expanded(
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
                      if (name != null && name.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(name, style: AppTypography.productMeta()),
                      ],
                    ],
                  ),
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
            Text(
              'Отправил: $sender · ${formatWhen(item.createdAt)}',
              style: AppTypography.productMeta(),
            ),
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