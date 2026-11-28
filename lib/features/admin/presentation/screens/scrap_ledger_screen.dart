import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../core/services/database_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/models/scrap_ledger_record.dart';
import '../widgets/admin_toast.dart';
import '../widgets/scrap_ledger_ui.dart';

/// Учёт и списание лома по весу и пробе (RPC 078).
class ScrapLedgerScreen extends StatelessWidget {
  const ScrapLedgerScreen({
    super.key,
    required this.database,
    this.sellerCode,
    this.initialBranch,
  });

  final DatabaseService database;
  final String? sellerCode;
  final String? initialBranch;

  static Future<void> open(
    BuildContext context, {
    required DatabaseService database,
    String? sellerCode,
    String? initialBranch,
  }) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ScrapLedgerScreen(
          database: database,
          sellerCode: sellerCode,
          initialBranch: initialBranch,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Учёт и списание лома',
          style: AppTypography.heading(fontSize: 20),
        ),
      ),
      body: ScrapLedgerPanel(
        database: database,
        sellerCode: sellerCode,
        initialBranch: initialBranch,
      ),
    );
  }
}

/// Вкладка или отдельный экран: остатки, списание, журнал.
class ScrapLedgerPanel extends StatefulWidget {
  const ScrapLedgerPanel({
    super.key,
    required this.database,
    this.sellerCode,
    this.initialBranch,
    this.embedded = false,
  });

  final DatabaseService database;
  final String? sellerCode;
  final String? initialBranch;
  final bool embedded;

  @override
  State<ScrapLedgerPanel> createState() => _ScrapLedgerPanelState();
}

class _ScrapLedgerPanelState extends State<ScrapLedgerPanel>
    with SingleTickerProviderStateMixin {
  static const _mobileBreakpoint = 900.0;

  late final TabController _mobileTabs;
  late String _branch;
  var _balancesLoading = true;
  var _journalLoading = true;
  String? _error;

  List<ScrapBalanceRow> _balanceRows = const [];
  List<ScrapBranchTotal> _branchTotals = const [];
  ScrapGrandTotal? _grandTotal;

  List<ScrapLedgerEntry> _journal = const [];
  int _journalTotal = 0;
  String _journalFilter = 'all';
  String? _journalPurity;
  DateTimeRange? _journalRange;

  /// Сбрасывает устаревшие ответы RPC при быстром переключении филиала.
  int _fetchGeneration = 0;

  @override
  void initState() {
    super.initState();
    _mobileTabs = TabController(length: 2, vsync: this);
    if (widget.embedded) {
      _branch = 'ALL';
    } else {
      final seed = widget.initialBranch?.trim().toUpperCase();
      _branch = seed == 'ICN' || seed == 'ANS' ? seed! : 'ALL';
    }
    _reloadAll();
  }

  @override
  void dispose() {
    _mobileTabs.dispose();
    super.dispose();
  }

  Future<void> _reloadAll() async {
    final generation = ++_fetchGeneration;
    await Future.wait([
      _loadBalances(generation: generation),
      _loadJournal(generation: generation, reset: true),
    ]);
  }

  String? get _rpcBranch =>
      _branch == 'ALL' || _branch.isEmpty ? null : _branch;

  Future<void> _loadBalances({required int generation}) async {
    setState(() {
      _balancesLoading = true;
      _error = null;
    });
    final result = await widget.database.getScrapBalances(
      branch: _rpcBranch,
    );
    if (!mounted || generation != _fetchGeneration) return;
    if (result['ok'] != true) {
      setState(() {
        _balancesLoading = false;
        _error = scrapLedgerErrorMessage(result['error']);
      });
      return;
    }
    setState(() {
      _balanceRows = ScrapBalanceRow.listFromRows(result['rows']);
      _branchTotals = ScrapBalanceRow.branchTotalsFrom(result['by_branch']);
      _grandTotal = ScrapBalanceRow.grandFrom(result['total']);
      _balancesLoading = false;
    });
  }

  Future<void> _loadJournal({
    required int generation,
    bool reset = false,
  }) async {
    setState(() => _journalLoading = true);
    final range = _journalRange;
    String? from;
    String? to;
    if (range != null) {
      from = _isoDateKst(range.start);
      to = _isoDateKst(range.end);
    }
    final result = await widget.database.listScrapLedger(
      branch: _rpcBranch,
      purity: _journalPurity,
      filter: _journalFilter,
      dateFromKst: from,
      dateToKst: to,
      limit: 80,
      offset: 0,
    );
    if (!mounted || generation != _fetchGeneration) return;
    if (result['ok'] != true) {
      setState(() => _journalLoading = false);
      if (_error == null) {
        setState(() => _error = scrapLedgerErrorMessage(result['error']));
      }
      return;
    }
    setState(() {
      _journal = ScrapLedgerEntry.listFromRpc(result);
      _journalTotal = (result['total'] as num?)?.round() ?? _journal.length;
      _journalLoading = false;
    });
  }

  static String _isoDateKst(DateTime date) {
    final kst = date.toUtc().add(const Duration(hours: 9));
    return DateFormat('yyyy-MM-dd').format(kst);
  }

  List<ScrapBalanceRow> get _visibleBalances {
    final rows = _balanceRows.where(
      (r) =>
          r.operationCount > 0 ||
          r.totalWeightG.abs() > 0.0005 ||
          r.totalIntakeG > 0,
    );
    if (_branch == 'ALL') return rows.toList();
    return rows.where((r) => r.branch == _branch).toList();
  }

  /// На «Все» — одна карточка на пробу (сумма ICN + ANS).
  List<ScrapBalanceRow> _displayBalanceCards() {
    final base = _visibleBalances.toList();
    if (_branch != 'ALL') {
      base.sort((a, b) {
        return (double.tryParse(a.purity) ?? 0).compareTo(
          double.tryParse(b.purity) ?? 0,
        );
      });
      return base;
    }

    final byPurity = <String, ScrapBalanceRow>{};
    for (final row in base) {
      final key = row.purity;
      final existing = byPurity[key];
      if (existing == null) {
        byPurity[key] = ScrapBalanceRow(
          branch: 'ALL',
          purity: row.purity,
          totalWeightG: row.totalWeightG,
          totalIntakeG: row.totalIntakeG,
          totalWriteoffG: row.totalWriteoffG,
          operationCount: row.operationCount,
        );
      } else {
        byPurity[key] = ScrapBalanceRow(
          branch: 'ALL',
          purity: row.purity,
          totalWeightG: existing.totalWeightG + row.totalWeightG,
          totalIntakeG: existing.totalIntakeG + row.totalIntakeG,
          totalWriteoffG: existing.totalWriteoffG + row.totalWriteoffG,
          operationCount: existing.operationCount + row.operationCount,
        );
      }
    }
    final merged = byPurity.values.toList()
      ..sort((a, b) {
        return (double.tryParse(a.purity) ?? 0).compareTo(
          double.tryParse(b.purity) ?? 0,
        );
      });
    return merged;
  }

  String? _branchHintForPurity(String purity) {
    final parts = _visibleBalances
        .where((r) => r.purity == purity && r.totalWeightG > 0.0005)
        .map((r) => r.branch)
        .toSet()
        .toList()
      ..sort();
    if (parts.isEmpty) return null;
    return parts.map(scrapLedgerBranchLabel).join(' · ');
  }

  Set<String> get _journalPurityOptions {
    return {
      for (final r in _balanceRows)
        if (r.purity.isNotEmpty) r.purity,
    };
  }

  Future<void> _openWriteOff({
    String? branch,
    String? purity,
    double? availableG,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => _ScrapWriteOffDialog(
        database: widget.database,
        sellerCode: widget.sellerCode,
        branch: branch ?? (_branch == 'ALL' ? null : _branch),
        purity: purity,
        availableG: availableG,
        balanceRows: _balanceRows,
      ),
    );
    if (ok == true) {
      await _reloadAll();
    }
  }

  Future<void> _pickJournalRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: _journalRange,
      locale: const Locale('ru', 'RU'),
      helpText: 'Период журнала (KST)',
    );
    if (picked == null || !mounted) return;
    setState(() => _journalRange = picked);
    final generation = ++_fetchGeneration;
    await _loadJournal(generation: generation);
  }

  Future<void> _onBranchChanged(Set<String> next) async {
    setState(() => _branch = next.first);
    final generation = ++_fetchGeneration;
    await Future.wait([
      _loadBalances(generation: generation),
      _loadJournal(generation: generation, reset: true),
    ]);
  }

  Future<void> _reloadJournalOnly() async {
    final generation = ++_fetchGeneration;
    await _loadJournal(generation: generation);
  }

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < _mobileBreakpoint;
    final balancesBody = _buildBalancesSection();
    final journalBody = _buildJournalSection();

    if (narrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildBranchBar(),
          if (_error != null) _errorBanner(),
          TabBar(
            controller: _mobileTabs,
            tabs: const [
              Tab(text: 'Остатки'),
              Tab(text: 'Журнал'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _mobileTabs,
              children: [
                Column(
                  children: [
                    Expanded(child: balancesBody),
                    _writeOffFooter(),
                  ],
                ),
                Column(
                  children: [
                    _buildJournalFilters(compact: true),
                    Expanded(child: journalBody),
                  ],
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildBranchBar(),
        if (_error != null) _errorBanner(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _reloadAll,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                balancesBody,
                const Divider(height: 24, thickness: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Журнал движений ($_journalTotal)',
                    style: AppTypography.productTitle.copyWith(fontSize: 16),
                  ),
                ),
                _buildJournalFilters(compact: false),
                SizedBox(
                  height: 360,
                  child: journalBody,
                ),
              ],
            ),
          ),
        ),
        _writeOffFooter(),
      ],
    );
  }

  Widget _errorBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Text(
        _error!,
        style: AppTypography.productMeta().copyWith(color: AppColors.saleRed),
      ),
    );
  }

  Widget _buildBranchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('Филиал:', style: AppTypography.productMeta()),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'ALL', label: Text('Все')),
              ButtonSegment(value: 'ICN', label: Text('ICN')),
              ButtonSegment(value: 'ANS', label: Text('ANS')),
            ],
            selected: {_branch},
            onSelectionChanged: _onBranchChanged,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
          ),
          IconButton(
            tooltip: 'Обновить',
            onPressed: _reloadAll,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }

  Widget _buildBalancesSection() {
    if (_balancesLoading) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final cards = _displayBalanceCards();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_branch == 'ALL' && _branchTotals.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final b in _branchTotals)
                  _SummaryChip(
                    label: scrapLedgerBranchLabel(b.branch),
                    weightG: b.totalWeightG,
                  ),
                if (_grandTotal != null)
                  _SummaryChip(
                    label: 'Всего',
                    weightG: _grandTotal!.totalWeightG,
                    emphasize: true,
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          if (cards.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Text(
                  _branch == 'ALL'
                      ? 'Движений лома в журнале пока нет. После приёмки или Trade-In остатки появятся здесь.'
                      : 'На точке ${scrapLedgerBranchLabel(_branch)} остаток лома 0 г. Оформите приёмку лома или Trade-In.',
                  style: AppTypography.productMeta(),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 700;
                final cross = wide ? 3 : 1;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cross,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                    childAspectRatio: wide ? 1.55 : 1.9,
                  ),
                  itemCount: cards.length,
                  itemBuilder: (context, index) {
                    final row = cards[index];
                    final showWrite = row.totalWeightG > 0.0005;
                    final branchHint = _branch == 'ALL' && row.branch == 'ALL'
                        ? _branchHintForPurity(row.purity)
                        : null;
                    return _PurityBalanceCard(
                      row: row,
                      showBranch: _branch == 'ALL' && row.branch != 'ALL',
                      branchHint: branchHint,
                      onWriteOff: showWrite
                          ? () => _openWriteOff(
                                branch: row.branch == 'ALL'
                                    ? null
                                    : row.branch,
                                purity: row.purity,
                                availableG: row.branch == 'ALL'
                                    ? null
                                    : row.totalWeightG,
                              )
                          : null,
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildJournalFilters({required bool compact}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          ChoiceChip(
            label: const Text('Все'),
            selected: _journalFilter == 'all',
            onSelected: (_) => _setJournalFilter('all'),
          ),
          ChoiceChip(
            label: const Text('Приход'),
            selected: _journalFilter == 'intake',
            onSelected: (_) => _setJournalFilter('intake'),
          ),
          ChoiceChip(
            label: const Text('Списание'),
            selected: _journalFilter == 'write_off',
            onSelected: (_) => _setJournalFilter('write_off'),
          ),
          DropdownButton<String?>(
            value: _journalPurity,
            hint: const Text('Все пробы'),
            items: [
              const DropdownMenuItem(value: null, child: Text('Все пробы')),
              for (final p in _journalPurityOptions.toList()..sort())
                DropdownMenuItem(value: p, child: Text('$p°')),
            ],
            onChanged: (v) {
              setState(() => _journalPurity = v);
              _reloadJournalOnly();
            },
          ),
          OutlinedButton.icon(
            onPressed: _pickJournalRange,
            icon: const Icon(Icons.date_range, size: 18),
            label: Text(
              _journalRange == null
                  ? 'Период'
                  : '${DateFormat('d.M.y').format(_journalRange!.start)} – ${DateFormat('d.M.y').format(_journalRange!.end)}',
            ),
          ),
          if (_journalRange != null)
            TextButton(
              onPressed: () {
                setState(() => _journalRange = null);
                _reloadJournalOnly();
              },
              child: const Text('Сбросить даты'),
            ),
        ],
      ),
    );
  }

  void _setJournalFilter(String filter) {
    setState(() => _journalFilter = filter);
    _reloadJournalOnly();
  }

  Widget _buildJournalSection() {
    if (_journalLoading && _journal.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_journal.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text('Записей не найдено.', style: AppTypography.productMeta()),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      itemCount: _journal.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) => _JournalTile(entry: _journal[index]),
    );
  }

  Widget _writeOffFooter() {
    return SafeArea(
      top: false,
      child: Material(
        elevation: 2,
        color: AppColors.cardBackground,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _openWriteOff(),
              icon: const Icon(Icons.output_outlined),
              label: const Text('Списать / Передать лом'),
            ),
          ),
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.weightG,
    this.emphasize = false,
  });

  final String label;
  final double weightG;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final style = emphasize
        ? AppTypography.productTitle.copyWith(fontWeight: FontWeight.w700)
        : AppTypography.productMeta();
    return Chip(
      label: Text('$label · ${formatScrapGrams(weightG)}', style: style),
    );
  }
}

class _PurityBalanceCard extends StatelessWidget {
  const _PurityBalanceCard({
    required this.row,
    required this.showBranch,
    this.branchHint,
    this.onWriteOff,
  });

  final ScrapBalanceRow row;
  final bool showBranch;
  final String? branchHint;
  final VoidCallback? onWriteOff;

  @override
  Widget build(BuildContext context) {
    final meta = AppTypography.productMeta();
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
            Text(scrapPurityTitle(row.purity), style: AppTypography.productTitle),
            if (showBranch) ...[
              const SizedBox(height: 2),
              Text(scrapLedgerBranchLabel(row.branch), style: meta),
            ] else if (branchHint != null && branchHint!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(branchHint!, style: meta),
            ],
            const SizedBox(height: 8),
            Text(
              formatScrapGrams(row.totalWeightG),
              style: AppTypography.heading(fontSize: 22),
            ),
            const SizedBox(height: 4),
            Text(
              'Приход: ${formatScrapDelta(row.totalIntakeG)} · '
              'Списано: ${formatScrapDelta(-row.totalWriteoffG)}',
              style: meta.copyWith(fontSize: 12),
            ),
            const Spacer(),
            if (onWriteOff != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: onWriteOff,
                  child: const Text('Списать'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _JournalTile extends StatelessWidget {
  const _JournalTile({required this.entry});

  final ScrapLedgerEntry entry;

  @override
  Widget build(BuildContext context) {
    final meta = AppTypography.productMeta();
    final delta = entry.weightDeltaG;
    final deltaColor = delta > 0
        ? const Color(0xFF2E7D32)
        : (delta < 0 ? AppColors.saleRed : AppColors.textSecondary);
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(scrapLedgerWhen(entry.createdAt), style: meta),
                Text(scrapLedgerBranchLabel(entry.branch), style: meta),
                Text('${entry.purity}°', style: meta.copyWith(fontWeight: FontWeight.w600)),
                ScrapMovementBadge(type: entry.movementType),
                Text(
                  formatScrapDelta(delta),
                  style: meta.copyWith(
                    color: deltaColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            if (entry.recipientOrReason != null)
              Text(entry.recipientOrReason!, style: meta.copyWith(fontSize: 12)),
            if (entry.comment != null)
              Text(entry.comment!, style: meta.copyWith(fontSize: 12)),
            if (entry.sellerCode != null || entry.createdBy != null)
              Text(
                [
                  if (entry.sellerCode != null) entry.sellerCode,
                  if (entry.createdBy != null && entry.createdBy != entry.sellerCode)
                    entry.createdBy,
                ].join(' · '),
                style: meta.copyWith(fontSize: 11, color: AppColors.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}

class _ScrapWriteOffDialog extends StatefulWidget {
  const _ScrapWriteOffDialog({
    required this.database,
    required this.balanceRows,
    this.sellerCode,
    this.branch,
    this.purity,
    this.availableG,
  });

  final DatabaseService database;
  final List<ScrapBalanceRow> balanceRows;
  final String? sellerCode;
  final String? branch;
  final String? purity;
  final double? availableG;

  @override
  State<_ScrapWriteOffDialog> createState() => _ScrapWriteOffDialogState();
}

class _ScrapWriteOffDialogState extends State<_ScrapWriteOffDialog> {
  static const _reasonChips = <(String, String)>[
    ('Переплавка / Аффинаж', 'write_off'),
    ('Передача поставщику / заводу', 'write_off'),
    ('Инвентаризационная корректировка', 'adjustment'),
  ];

  late String _branch;
  String? _purity;
  late final TextEditingController _weight;
  late final TextEditingController _reason;
  late final TextEditingController _comment;
  String _movementType = 'write_off';
  var _busy = false;
  String? _error;
  String? _weightError;

  @override
  void initState() {
    super.initState();
    _purity = widget.purity;
    final purityOpts = _purity != null
        ? _options.where((o) => o.purity == _purity).toList()
        : <({String branch, String purity, double available})>[];
    if (widget.branch != null) {
      _branch = widget.branch!;
    } else if (purityOpts.isNotEmpty) {
      _branch = purityOpts.first.branch;
    } else {
      _branch = _options.isNotEmpty ? _options.first.branch : 'ICN';
    }
    final avail = widget.availableG ?? 0;
    _weight = TextEditingController(
      text: avail > 0 ? avail.toStringAsFixed(2) : '',
    );
    _reason = TextEditingController();
    _comment = TextEditingController();
    if (_purity == null) {
      final opts = _options.where((o) => o.branch == _branch).toList();
      if (opts.isNotEmpty) {
        _purity = opts.first.purity;
        _weight.text = opts.first.available.toStringAsFixed(2);
      }
    } else if (avail <= 0 && purityOpts.isNotEmpty) {
      final match =
          purityOpts.where((o) => o.branch == _branch).firstOrNull ??
              purityOpts.first;
      _weight.text = match.available.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _weight.dispose();
    _reason.dispose();
    _comment.dispose();
    super.dispose();
  }

  List<({String branch, String purity, double available})> get _options {
    final out = <({String branch, String purity, double available})>[];
    for (final r in widget.balanceRows) {
      if (r.totalWeightG <= 0.0005) continue;
      out.add((branch: r.branch, purity: r.purity, available: r.totalWeightG));
    }
    out.sort((a, b) {
      final bc = a.branch.compareTo(b.branch);
      if (bc != 0) return bc;
      return a.purity.compareTo(b.purity);
    });
    return out;
  }

  double get _available {
    if (_purity == null) return 0;
    for (final o in _options) {
      if (o.branch == _branch && o.purity == _purity) return o.available;
    }
    return 0;
  }

  void _fillAllWeight() {
    final a = _available;
    if (a <= 0) return;
    setState(() {
      _weight.text = a.toStringAsFixed(2);
      _weightError = null;
    });
  }

  bool _validateWeight() {
    final raw = _weight.text.trim().replaceAll(',', '.');
    final value = double.tryParse(raw) ?? 0;
    if (value <= 0) {
      setState(() => _weightError = 'Вес должен быть больше 0.');
      return false;
    }
    if (value > _available + 0.0001) {
      setState(
        () => _weightError =
            'Максимум ${formatScrapGrams(_available)} на остатке.',
      );
      return false;
    }
    setState(() => _weightError = null);
    return true;
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (_purity == null) {
      setState(() => _error = 'Выберите пробу.');
      return;
    }
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = scrapLedgerErrorMessage('recipient_required'));
      return;
    }
    if (!_validateWeight()) return;

    final raw = _weight.text.trim().replaceAll(',', '.');
    final weight = double.tryParse(raw) ?? 0;

    setState(() {
      _busy = true;
      _error = null;
    });
    final result = await widget.database.writeOffScrap(
      branch: _branch,
      purity: _purity!,
      weightG: weight,
      movementType: _movementType,
      recipientOrReason: reason,
      comment: _comment.text,
      sellerCode: widget.sellerCode,
    );
    if (!mounted) return;
    if (result['ok'] == true) {
      final host = ScaffoldMessenger.of(context).context;
      Navigator.of(context).pop(true);
      final balance = result['balance_g'];
      if (host.mounted) {
        showAdminToast(
          host,
          'Списано ${formatScrapGrams(weight)}. Остаток ${formatScrapGrams(balance is num ? balance.toDouble() : _available - weight)}.',
        );
      }
      return;
    }
    setState(() {
      _busy = false;
      _error = scrapLedgerErrorMessage(result['error']);
    });
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height;
    final meta = AppTypography.productMeta();
    final puritiesForBranch = _options.where((o) => o.branch == _branch).toList();

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 520, maxHeight: height * 0.92),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Списать / Передать лом',
                      style: AppTypography.heading(fontSize: 18),
                    ),
                  ),
                  IconButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _branch,
                      decoration: const InputDecoration(
                        labelText: 'Филиал',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'ICN', child: Text('Инчхон (ICN)')),
                        DropdownMenuItem(value: 'ANS', child: Text('Ансан (ANS)')),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) {
                              if (v == null) return;
                              setState(() {
                                _branch = v;
                                _purity = null;
                                _weight.clear();
                              });
                            },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _purity,
                      decoration: const InputDecoration(
                        labelText: 'Проба',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final o in puritiesForBranch)
                          DropdownMenuItem(
                            value: o.purity,
                            child: Text(
                              '${o.purity}° (доступно: ${formatScrapGrams(o.available)})',
                            ),
                          ),
                      ],
                      onChanged: _busy || puritiesForBranch.isEmpty
                          ? null
                          : (v) => setState(() {
                                _purity = v;
                                _fillAllWeight();
                              }),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _weight,
                      enabled: !_busy,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Вес к списанию, г',
                        border: const OutlineInputBorder(),
                        errorText: _weightError,
                        suffixIcon: TextButton(
                          onPressed: _busy ? null : _fillAllWeight,
                          child: const Text('Весь остаток'),
                        ),
                      ),
                      onChanged: (_) => _validateWeight(),
                    ),
                    const SizedBox(height: 12),
                    Text('Куда передан / причина', style: meta),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final chip in _reasonChips)
                          ActionChip(
                            label: Text(chip.$1),
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                      _reason.text = chip.$1;
                                      _movementType = chip.$2;
                                    }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _reason,
                      enabled: !_busy,
                      decoration: const InputDecoration(
                        labelText: 'Причина (обязательно)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _comment,
                      enabled: !_busy,
                      minLines: 2,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Комментарий',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Операция списывает только вес металла в граммах и не влияет на кассу смены.',
                      style: meta.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: TextStyle(color: AppColors.saleRed)),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      child: const Text('Отмена'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Списать'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}