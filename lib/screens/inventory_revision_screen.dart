import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/services/database_service.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../core/utils/store_location_utils.dart';
import '../features/admin/presentation/widgets/admin_toast.dart';
import '../utils/jewelry_qr_parser.dart';
import '../widgets/universal_qr_scanner_sheet.dart';

/// Совместная QR-ревизия витрин (админ + продавцы).
class InventoryRevisionScreen extends StatefulWidget {
  const InventoryRevisionScreen({
    super.key,
    this.database,
    this.scannerDisplayName = 'Сотрудник',
  });

  final DatabaseService? database;
  final String scannerDisplayName;

  @override
  State<InventoryRevisionScreen> createState() =>
      _InventoryRevisionScreenState();
}

class _InventoryRevisionScreenState extends State<InventoryRevisionScreen>
    with SingleTickerProviderStateMixin {
  late final DatabaseService _database =
      widget.database ?? DatabaseService.create();
  late final TabController _tabs = TabController(length: 2, vsync: this);

  Map<String, dynamic>? _activeSession;
  List<Map<String, dynamic>> _scans = const [];
  List<Map<String, dynamic>> _history = const [];
  bool _busy = false;

  RealtimeChannel? _scanChannel;
  RealtimeChannel? _sessionChannel;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _tabs.dispose();
    unawaited(_scanChannel?.unsubscribe());
    unawaited(_sessionChannel?.unsubscribe());
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _reloadActive();
    await _loadHistory();
    _subscribeRealtime();
  }

  void _subscribeRealtime() {
    _sessionChannel = Supabase.instance.client
        .channel('inventory_revision_sessions')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'inventory_sessions',
          callback: (_) {
            unawaited(_reloadActive());
            unawaited(_loadHistory());
          },
        )
        .subscribe();

    final sessionId = _activeSession?['id']?.toString();
    if (sessionId != null) {
      _bindScansChannel(sessionId);
    }
  }

  void _bindScansChannel(String sessionId) {
    unawaited(_scanChannel?.unsubscribe());
    _scanChannel = Supabase.instance.client
        .channel('inventory_revision_scans_$sessionId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'inventory_session_scans',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'session_id',
            value: sessionId,
          ),
          callback: (_) {
            unawaited(_reloadScans(sessionId));
          },
        )
        .subscribe();
  }

  Future<void> _reloadActive() async {
    setState(() => _busy = true);
    try {
      final session = await _database.fetchActiveInventorySession();
      if (!mounted) return;
      setState(() => _activeSession = session);
      final id = session?['id']?.toString();
      if (id != null) {
        _bindScansChannel(id);
        await _reloadScans(id);
      } else {
        setState(() => _scans = const []);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reloadScans(String sessionId) async {
    final rows = await _database.listInventorySessionScans(sessionId);
    if (!mounted) return;
    setState(() => _scans = rows);
  }

  Future<void> _loadHistory() async {
    final rows = await _database.listCompletedInventorySessions();
    if (!mounted) return;
    setState(() => _history = rows);
  }

  Future<void> _startSession(String branch) async {
    setState(() => _busy = true);
    try {
      final id = await _database.startInventorySession(
        branchScope: branch,
        starterName: widget.scannerDisplayName,
      );
      if (!mounted) return;
      if (id == null) {
        showAdminToast(context, 'Не удалось начать (возможно, ревизия уже идёт)', error: true);
        await _reloadActive();
        return;
      }
      showAdminToast(context, 'Ревизия начата');
      await _reloadActive();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _completeSession() async {
    final session = _activeSession;
    final id = session?['id']?.toString();
    if (id == null) return;
    setState(() => _busy = true);
    try {
      final result = await _database.completeInventorySession(id);
      if (!mounted) return;
      if (result['ok'] == true) {
        final summary = result['summary'];
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Ревизия завершена'),
            content: SingleChildScrollView(
              child: Text(summary?.toString() ?? 'Готово'),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        await _reloadActive();
        await _loadHistory();
      } else {
        showAdminToast(context, 'Ошибка завершения', error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openScanner() async {
    final session = _activeSession;
    final sessionId = session?['id']?.toString();
    if (sessionId == null) return;
    await UniversalQrScannerSheet.show(
      context,
      title: 'Ревизия · сканирование',
      onScan: (payload) => _handleRevisionScan(sessionId, payload),
    );
  }

  Future<void> _handleRevisionScan(String sessionId, String raw) async {
    final result = await _database.recordInventoryScan(
      sessionId: sessionId,
      rawPayload: JewelryQrParser.parse(raw).lookupKey,
      scannerName: widget.scannerDisplayName,
    );
    if (!mounted) return;
    if (result['ok'] != true) {
      showAdminToast(context, 'Ошибка скана', error: true);
      return;
    }
    if (result['duplicate'] == true) {
      final who = result['scanned_by_name']?.toString() ?? 'коллега';
      showAdminToast(context, 'Уже отсканировано: $who');
      return;
    }
    final kind = result['scan_result']?.toString() ?? '';
    final sku = result['product_sku']?.toString() ?? '';
    final message = switch (kind) {
      'matched' => 'OK: $sku',
      'wrong_store' => 'Чужая витрина: $sku',
      'wrong_status' => 'Статус/остаток: $sku',
      'unknown' => 'Неизвестный QR',
      _ => 'Скан: $sku',
    };
    showAdminToast(context, message, error: kind != 'matched');
    await _reloadScans(sessionId);
  }

  _ScanStats _stats() {
    final session = _activeSession;
    final expected = (session?['expected_count'] as num?)?.toInt() ?? 0;
    var wrong = 0;
    var unknown = 0;
    final matchedIds = <String>{};
    for (final scan in _scans) {
      final kind = scan['scan_result']?.toString();
      if (kind == 'matched') {
        final pid = scan['product_id']?.toString();
        if (pid != null) matchedIds.add(pid);
      } else if (kind == 'unknown') {
        unknown++;
      } else if (kind == 'wrong_store' || kind == 'wrong_status') {
        wrong++;
      }
    }
    final missing = expected - matchedIds.length;
    return _ScanStats(
      expected: expected,
      matched: matchedIds.length,
      remaining: missing.clamp(0, expected),
      wrong: wrong,
      unknown: unknown,
    );
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats();
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            controller: _tabs,
            labelStyle: AppTypography.caption(fontWeight: FontWeight.w700),
            tabs: const [
              Tab(text: 'Текущая ревизия'),
              Tab(text: 'История ревизий'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _CurrentRevisionTab(
                  busy: _busy,
                  session: _activeSession,
                  scans: _scans,
                  stats: stats,
                  onStart: _startSession,
                  onScan: _openScanner,
                  onComplete: _completeSession,
                ),
                _HistoryTab(
                  history: _history,
                  onOpen: (session) => _openHistoryDetail(session),
                ),
              ],
            ),
          ),
          if (_activeSession != null)
            Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, bottom + 12),
              child: FilledButton.icon(
                onPressed: _busy ? null : _openScanner,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Сканировать камерой'),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openHistoryDetail(Map<String, dynamic> session) async {
    final id = session['id']?.toString();
    if (id == null) return;
    final scans = await _database.listInventorySessionScans(id);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Ревизия ${session['branch_scope']} · '
          '${session['completed_at']?.toString().substring(0, 16) ?? ''}',
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Старт: ${session['started_by_name']}'),
                Text('Итог: ${session['summary']}'),
                const Divider(),
                Text('Сканов: ${scans.length}'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }
}

class _ScanStats {
  const _ScanStats({
    required this.expected,
    required this.matched,
    required this.remaining,
    required this.wrong,
    required this.unknown,
  });

  final int expected;
  final int matched;
  final int remaining;
  final int wrong;
  final int unknown;
}

class _CurrentRevisionTab extends StatelessWidget {
  const _CurrentRevisionTab({
    required this.busy,
    required this.session,
    required this.scans,
    required this.stats,
    required this.onStart,
    required this.onScan,
    required this.onComplete,
  });

  final bool busy;
  final Map<String, dynamic>? session;
  final List<Map<String, dynamic>> scans;
  final _ScanStats stats;
  final Future<void> Function(String branch) onStart;
  final Future<void> Function() onScan;
  final Future<void> Function() onComplete;

  @override
  Widget build(BuildContext context) {
    if (session == null) {
      return _StartRevisionBody(busy: busy, onStart: onStart);
    }

    final branch = session!['branch_scope']?.toString() ?? 'ALL';
  final starter = session!['started_by_name']?.toString() ?? '';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Активная ревизия',
          style: AppTypography.heading(fontSize: 18),
        ),
        const SizedBox(height: 8),
        Text(
          '${storeLocationDisplayLabel(branch)} · запустил(а): $starter',
          style: AppTypography.productMeta(),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _StatChip(label: 'Ожидается', value: '${stats.expected}'),
            _StatChip(
              label: 'Сошлось',
              value: '${stats.matched}',
              color: const Color(0xFF1B5E20),
            ),
            _StatChip(label: 'Осталось', value: '${stats.remaining}'),
            _StatChip(
              label: 'Чужая/статус',
              value: '${stats.wrong}',
              color: AppColors.saleRed,
            ),
            _StatChip(label: 'Неизвестный QR', value: '${stats.unknown}'),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            OutlinedButton.icon(
              onPressed: busy ? null : onScan,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Подключиться к сканированию'),
            ),
            const Spacer(),
            FilledButton(
              onPressed: busy ? null : onComplete,
              child: const Text('Сверить и завершить'),
            ),
          ],
        ),
        const Divider(height: 24),
        Text('Последние сканы', style: AppTypography.heading(fontSize: 16)),
        const SizedBox(height: 8),
        ...scans.take(40).map(_scanTile),
      ],
    );
  }

  Widget _scanTile(Map<String, dynamic> scan) {
    final sku = scan['product_sku']?.toString().ifEmpty ?? '—';
    final who = scan['scanned_by_name']?.toString() ?? '';
    final kind = scan['scan_result']?.toString() ?? '';
    final color = switch (kind) {
      'matched' => const Color(0xFF1B5E20),
      'unknown' => Colors.grey,
      _ => AppColors.saleRed,
    };
    return ListTile(
      dense: true,
      leading: Icon(Icons.qr_code_2, color: color, size: 20),
      title: Text(sku),
      subtitle: Text('$who · $kind'),
    );
  }
}

class _StartRevisionBody extends StatefulWidget {
  const _StartRevisionBody({
    required this.busy,
    required this.onStart,
  });

  final bool busy;
  final Future<void> Function(String branch) onStart;

  @override
  State<_StartRevisionBody> createState() => _StartRevisionBodyState();
}

class _StartRevisionBodyState extends State<_StartRevisionBody> {
  String _branch = 'ICN';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Нет активной ревизии',
            style: AppTypography.heading(fontSize: 18),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'ICN', label: Text('Инчхон')),
              ButtonSegment(value: 'ANS', label: Text('Ансан')),
              ButtonSegment(value: 'ALL', label: Text('Все')),
            ],
            selected: {_branch},
            onSelectionChanged: (set) {
              setState(() => _branch = set.first);
            },
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: widget.busy ? null : () => widget.onStart(_branch),
            child: const Text('Начать ревизию'),
          ),
        ],
      ),
    );
  }
}

class _HistoryTab extends StatelessWidget {
  const _HistoryTab({
    required this.history,
    required this.onOpen,
  });

  final List<Map<String, dynamic>> history;
  final ValueChanged<Map<String, dynamic>> onOpen;

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return Center(
        child: Text(
          'Завершённых ревизий пока нет',
          style: AppTypography.productMeta(),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: history.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final row = history[index];
        final branch = row['branch_scope']?.toString() ?? '';
        final starter = row['started_by_name']?.toString() ?? '';
        final summary = row['summary']?.toString() ?? '';
        final when = row['completed_at']?.toString().substring(0, 16) ?? '';
        return ListTile(
          title: Text('$when · ${storeLocationDisplayLabel(branch)}'),
          subtitle: Text('$starter · $summary'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => onOpen(row),
        );
      },
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    this.color,
  });

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: $value'),
      labelStyle: TextStyle(
        color: color ?? AppColors.primary,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

extension on String {
  String get ifEmpty => isEmpty ? '—' : this;
}