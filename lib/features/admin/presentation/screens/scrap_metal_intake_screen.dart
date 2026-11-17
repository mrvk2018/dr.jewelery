import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../../core/services/database_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/store_location_utils.dart';
import '../../../../core/utils/won_format.dart';
import '../../../profile/domain/models/user_profile.dart';
import '../../../../shared/models/seller_item.dart';
import '../../data/scrap_metal_storage.dart';
import '../../domain/scrap_metal_calculator.dart';

/// Приёмка лома: расчёт 585/925, журнал, списание со склада.
class ScrapMetalIntakeScreen extends StatefulWidget {
  ScrapMetalIntakeScreen({
    super.key,
    DatabaseService? database,
    this.initialSellerCode,
    this.initialSellerName,
    this.hideJournalBulkWriteOff = false,
    this.actorCode = 'ADMIN',
  }) : database = database ?? DatabaseService.create();

  final DatabaseService database;
  final String? initialSellerCode;
  final String? initialSellerName;
  final bool hideJournalBulkWriteOff;
  final String actorCode;

  @override
  State<ScrapMetalIntakeScreen> createState() => _ScrapMetalIntakeScreenState();
}

class _ScrapMetalIntakeScreenState extends State<ScrapMetalIntakeScreen>
    with SingleTickerProviderStateMixin {
  static const _adminAcceptKey = 'ADMIN';
  static const _maxPhotos = 2;

  late final TabController _tabs;

  String _storeLocation = StoreLocationCode.icn;
  String _acceptKey = _adminAcceptKey;
  List<SellerItem> _sellers = const [];
  bool _loadingSellers = true;

  final _notesController = TextEditingController();
  final List<ScrapFinenessRow> _goldRows = _defaultGoldRows();
  final List<ScrapFinenessRow> _silverRows = _defaultSilverRows();
  final List<String> _photoUrls = [];
  final List<Uint8List> _pendingPhotoBytes = [];

  final _goldStdRate = TextEditingController();
  final _goldTradeRate = TextEditingController();
  final _goldPurchaseGrams = TextEditingController(text: '0');
  final _silverStdRate = TextEditingController();
  final _silverTradeRate = TextEditingController();
  final _silverPurchaseGrams = TextEditingController(text: '0');

  String? _editingId;
  bool _calculated = false;
  bool _saving = false;

  List<Map<String, dynamic>> _journal = const [];
  bool _journalLoading = false;
  String? _filterStore;
  String? _filterMetal;
  String? _filterStatus = 'in_stock';
  DateTime? _filterFrom;
  DateTime? _filterTo;
  final Set<String> _selectedJournalIds = {};
  String? _highlightPayout;

  ScrapPayoutBreakdown? _goldBreakdown;
  ScrapPayoutBreakdown? _silverBreakdown;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _tabs.addListener(() {
      if (_tabs.index == 1 && _tabs.indexIsChanging == false) {
        _loadJournal();
      }
    });
  if (widget.initialSellerCode != null &&
        widget.initialSellerName != null) {
      _acceptKey = widget.initialSellerCode!;
    }
    _bootstrap();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _notesController.dispose();
    _goldStdRate.dispose();
    _goldTradeRate.dispose();
    _goldPurchaseGrams.dispose();
    _silverStdRate.dispose();
    _silverTradeRate.dispose();
    _silverPurchaseGrams.dispose();
    super.dispose();
  }

  static List<ScrapFinenessRow> _defaultGoldRows() => [
        ScrapFinenessRow(fineness: 375),
        ScrapFinenessRow(fineness: 585),
        ScrapFinenessRow(fineness: 750),
        ScrapFinenessRow(fineness: 995),
      ];

  static List<ScrapFinenessRow> _defaultSilverRows() => [
        ScrapFinenessRow(fineness: 875),
        ScrapFinenessRow(fineness: 925),
        ScrapFinenessRow(fineness: 999),
      ];

  Future<void> _bootstrap() async {
    try {
      final storage = await ScrapMetalStorage.create();
      if (!mounted) return;
      setState(() => _storeLocation = storage.storeLocation);
      _goldStdRate.text = '${storage.goldStandardRateKrw}';
      _goldTradeRate.text = '${storage.goldTradeinRateKrw}';
      _silverStdRate.text = '${storage.silverStandardRateKrw}';
      _silverTradeRate.text = '${storage.silverTradeinRateKrw}';
    } catch (_) {}

    try {
      final sellers = await widget.database.getSellers(UserRole.admin);
      if (!mounted) return;
      setState(() {
        _sellers = sellers.where((s) => s.isActive).toList();
        _loadingSellers = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingSellers = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? AppColors.saleRed : AppColors.primary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _acceptName() {
    if (_acceptKey == _adminAcceptKey) return 'Администратор';
    for (final s in _sellers) {
      if (s.promoCode == _acceptKey) return s.name;
    }
    return 'Администратор';
  }

  int _parseInt(TextEditingController c) =>
      int.tryParse(c.text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;

  double _parseDouble(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '.')) ?? 0;

  void _runCalculate() {
    final goldEq = ScrapMetalCalculator.sumGoldEquivalent(_goldRows);
    final silverEq = ScrapMetalCalculator.sumSilverEquivalent(_silverRows);
    final gold = ScrapMetalCalculator.computePayout(
      totalEquivalent: goldEq,
      purchaseOffsetGrams: _parseDouble(_goldPurchaseGrams),
      standardRateKrw: _parseInt(_goldStdRate),
      tradeinRateKrw: _parseInt(_goldTradeRate),
    );
    final silver = ScrapMetalCalculator.computePayout(
      totalEquivalent: silverEq,
      purchaseOffsetGrams: _parseDouble(_silverPurchaseGrams),
      standardRateKrw: _parseInt(_silverStdRate),
      tradeinRateKrw: _parseInt(_silverTradeRate),
    );
    setState(() {
      _goldBreakdown = gold;
      _silverBreakdown = silver;
      _calculated = true;
      _highlightPayout =
          'Итого: ${formatWon(gold.payoutKrw + silver.payoutKrw)}';
    });
  }

  Future<void> _persistRates() async {
    final storage = await ScrapMetalStorage.create();
    await storage.saveStoreLocation(_storeLocation);
    await storage.saveGoldRates(
      standard: _parseInt(_goldStdRate),
      tradein: _parseInt(_goldTradeRate),
    );
    await storage.saveSilverRates(
      standard: _parseInt(_silverStdRate),
      tradein: _parseInt(_silverTradeRate),
    );
  }

  Map<String, dynamic> _buildPayload() {
    final goldItems = ScrapFinenessRow.activeRows(_goldRows)
        .map((r) => {
              'fineness': r.fineness,
              'gross_weight': r.grossWeight,
              'stone_discount_percent': r.stoneDiscountPercent,
            })
        .toList();
    final silverItems = ScrapFinenessRow.activeRows(_silverRows)
        .map((r) => {
              'fineness': r.fineness,
              'gross_weight': r.grossWeight,
              'stone_discount_percent': r.stoneDiscountPercent,
            })
        .toList();

    return {
      if (_editingId != null) 'id': _editingId,
      'store_location': _storeLocation,
      'accepted_by_code': _acceptKey == _adminAcceptKey ? 'ADMIN' : _acceptKey,
      'accepted_by_name': _acceptName(),
      'notes': _notesController.text.trim(),
      'photo_urls': List<String>.from(_photoUrls),
      'gold_items': goldItems,
      'gold_standard_rate_krw': _parseInt(_goldStdRate),
      'gold_tradein_rate_krw': _parseInt(_goldTradeRate),
      'gold_purchase_offset_grams': _parseDouble(_goldPurchaseGrams),
      'silver_items': silverItems,
      'silver_standard_rate_krw': _parseInt(_silverStdRate),
      'silver_tradein_rate_krw': _parseInt(_silverTradeRate),
      'silver_purchase_offset_grams': _parseDouble(_silverPurchaseGrams),
    };
  }

  Future<void> _pickPhoto() async {
    if (_photoUrls.length + _pendingPhotoBytes.length >= _maxPhotos) {
      _snack('Не более $_maxPhotos фото', error: true);
      return;
    }
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() => _pendingPhotoBytes.add(bytes));
  }

  Future<List<String>> _uploadPendingPhotos() async {
    final urls = <String>[..._photoUrls];
    for (final bytes in _pendingPhotoBytes) {
      final url = await widget.database.uploadScrapMetalIntakePhoto(
        bytes: bytes,
        contentType: 'image/jpeg',
      );
      if (url != null) urls.add(url);
    }
    return urls;
  }

  Future<void> _saveIntake() async {
    if (!_calculated) _runCalculate();
    setState(() => _saving = true);
    try {
      await _persistRates();
      final uploadedUrls = await _uploadPendingPhotos();
      final payload = _buildPayload()..['photo_urls'] = uploadedUrls;
      final result = await widget.database.upsertScrapMetalIntake(payload);
      if (!result.ok) {
        _snack(result.error ?? 'Не удалось сохранить', error: true);
        return;
      }
      _snack(_editingId == null ? 'Акт приёмки сохранён' : 'Изменения сохранены');
      setState(() {
        _pendingPhotoBytes.clear();
        _photoUrls
          ..clear()
          ..addAll(uploadedUrls);
        _editingId = null;
        _resetIntakeForm(keepRates: true);
      });
      if (_tabs.index == 1) await _loadJournal();
    } catch (error) {
      _snack('Ошибка: $error', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _resetIntakeForm({bool keepRates = false}) {
    _notesController.clear();
    _goldRows
      ..clear()
      ..addAll(_defaultGoldRows());
    _silverRows
      ..clear()
      ..addAll(_defaultSilverRows());
    if (!keepRates) {
      _goldPurchaseGrams.text = '0';
      _silverPurchaseGrams.text = '0';
    } else {
      _goldPurchaseGrams.text = '0';
      _silverPurchaseGrams.text = '0';
    }
    _photoUrls.clear();
    _pendingPhotoBytes.clear();
    _calculated = false;
    _goldBreakdown = null;
    _silverBreakdown = null;
    _acceptKey = widget.initialSellerCode ?? _adminAcceptKey;
  }

  void _loadActToForm(Map<String, dynamic> row) {
    setState(() {
      _editingId = row['id']?.toString();
      _storeLocation = row['store_location']?.toString() ?? StoreLocationCode.icn;
      final code = row['accepted_by_code']?.toString() ?? _adminAcceptKey;
      _acceptKey = code == 'ADMIN' ? _adminAcceptKey : code;
      _notesController.text = row['notes']?.toString() ?? '';
      _goldStdRate.text = '${row['gold_standard_rate_krw'] ?? 0}';
      _goldTradeRate.text = '${row['gold_tradein_rate_krw'] ?? 0}';
      _goldPurchaseGrams.text =
          '${row['gold_purchase_offset_grams'] ?? 0}';
      _silverStdRate.text = '${row['silver_standard_rate_krw'] ?? 0}';
      _silverTradeRate.text = '${row['silver_tradein_rate_krw'] ?? 0}';
      _silverPurchaseGrams.text =
          '${row['silver_purchase_offset_grams'] ?? 0}';
      _photoUrls
        ..clear()
        ..addAll(_parseUrlList(row['photo_urls']));
      _goldRows
        ..clear()
        ..addAll(_rowsFromJson(row['gold_items'], isGold: true));
      _silverRows
        ..clear()
        ..addAll(_rowsFromJson(row['silver_items'], isGold: false));
      _calculated = false;
    });
    _tabs.animateTo(0);
    _runCalculate();
  }

  static List<String> _parseUrlList(dynamic raw) {
    if (raw is! List) return [];
    return raw.map((e) => e.toString()).where((u) => u.isNotEmpty).toList();
  }

  static List<ScrapFinenessRow> _rowsFromJson(dynamic raw, {required bool isGold}) {
    if (raw is! List || raw.isEmpty) {
      return isGold ? _defaultGoldRows() : _defaultSilverRows();
    }
    final parsed = <ScrapFinenessRow>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final fineness = (item['fineness'] as num?)?.toDouble() ?? 0;
      if (fineness <= 0) continue;
      parsed.add(
        ScrapFinenessRow(
          fineness: fineness,
          grossWeight: (item['gross_weight'] as num?)?.toDouble() ?? 0,
          stoneDiscountPercent:
              (item['stone_discount_percent'] as num?)?.toDouble() ?? 0,
          customFineness: ![375, 585, 750, 995, 875, 925, 999].contains(fineness.round()),
        ),
      );
    }
    if (parsed.isEmpty) {
      return isGold ? _defaultGoldRows() : _defaultSilverRows();
    }
    return parsed;
  }

  Future<void> _loadJournal() async {
    setState(() => _journalLoading = true);
    final rows = await widget.database.listScrapMetalIntakes(
      storeLocation: _filterStore,
      metal: _filterMetal,
      status: _filterStatus,
      dateFrom: _filterFrom,
      dateTo: _filterTo,
    );
    if (!mounted) return;
    setState(() {
      _journal = rows;
      _journalLoading = false;
      _selectedJournalIds.removeWhere(
        (id) => !rows.any((r) => r['id']?.toString() == id),
      );
    });
  }

  Future<void> _writeOffSelected() async {
    final ids = _selectedJournalIds
        .where((id) {
          final row = _journal.cast<Map<String, dynamic>?>().firstWhere(
                (r) => r!['id']?.toString() == id,
                orElse: () => null,
              );
          return row != null && row['status']?.toString() == 'in_stock';
        })
        .toList();
    if (ids.isEmpty) {
      _snack('Выберите акты «На складе»', error: true);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Списать со склада?'),
        content: Text('Списать ${ids.length} акт(ов) в архив?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Списать')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final res = await widget.database.writeOffScrapMetalIntakes(ids: ids);
    if (!res.ok) {
      _snack(res.error ?? 'Ошибка', error: true);
      return;
    }
    _snack('Списано: ${res.writtenOff}');
    await _loadJournal();
  }

  Future<void> _deleteAct(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить акт?'),
        content: const Text('Запись будет удалена без восстановления.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.saleRed),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final res = await widget.database.deleteScrapMetalIntake(id);
    if (!res.ok) {
      _snack(res.error ?? 'Ошибка', error: true);
      return;
    }
    _snack('Акт удалён');
    await _loadJournal();
  }

  static String _formatKst(dynamic raw) {
    if (raw == null) return '—';
    DateTime? dt;
    if (raw is DateTime) {
      dt = raw;
    } else {
      dt = DateTime.tryParse(raw.toString());
    }
    if (dt == null) return raw.toString();
    final kst = dt.toUtc().add(const Duration(hours: 9));
    return DateFormat('dd.MM.yyyy HH:mm', 'ru').format(kst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('Приёмка лома', style: AppTypography.heading(fontSize: 20)),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Приёмка и расчёт'),
            Tab(text: 'Журнал и архив'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _buildIntakeTab(),
          _buildJournalTab(),
        ],
      ),
    );
  }

  Widget _buildIntakeTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHeaderCard(),
        const SizedBox(height: 16),
        _buildMetalSection(
          title: 'Золото (приведение к 585 пробе)',
          rows: _goldRows,
          standardProbe: 585,
          eqLabel: 'В 585 пробе',
          stdRate: _goldStdRate,
          tradeRate: _goldTradeRate,
          purchaseGrams: _goldPurchaseGrams,
          breakdown: _goldBreakdown,
          onAddCustom: () => setState(
            () => _goldRows.add(
              ScrapFinenessRow(fineness: 583, customFineness: true),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _buildMetalSection(
          title: 'Серебро (приведение к 925 пробе)',
          rows: _silverRows,
          standardProbe: 925,
          eqLabel: 'В 925 пробе',
          stdRate: _silverStdRate,
          tradeRate: _silverTradeRate,
          purchaseGrams: _silverPurchaseGrams,
          breakdown: _silverBreakdown,
          onAddCustom: () => setState(
            () => _silverRows.add(
              ScrapFinenessRow(fineness: 800, customFineness: true),
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_highlightPayout != null)
          Card(
            color: AppColors.accent.withValues(alpha: 0.12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _highlightPayout!,
                style: AppTypography.heading(fontSize: 18),
              ),
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(onPressed: _runCalculate, child: const Text('Рассчитать')),
            FilledButton(
              onPressed: _saving ? null : _saveIntake,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_editingId == null ? 'Сохранить акт приёмки' : 'Сохранить изменения в акте'),
            ),
            if (_editingId != null)
              TextButton(
                onPressed: () => setState(() {
                  _editingId = null;
                  _resetIntakeForm();
                }),
                child: const Text('Отменить редактирование'),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildHeaderCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Магазин',
              style: AppTypography.productMeta().copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _storeChip(StoreLocationCode.icn, 'Инчхон'),
                const SizedBox(width: 8),
                _storeChip(StoreLocationCode.ans, 'Ансан'),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _acceptKey,
              decoration: const InputDecoration(
                labelText: 'Кто принял',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(
                  value: _adminAcceptKey,
                  child: Text('Администратор'),
                ),
                ..._sellers.map(
                  (s) => DropdownMenuItem(
                    value: s.promoCode,
                    child: Text('${s.name} (${s.promoCode})'),
                  ),
                ),
              ],
              onChanged: _loadingSellers ? null : (v) => setState(() => _acceptKey = v ?? _adminAcceptKey),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Комментарий / клиент',
                border: OutlineInputBorder(),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _pickPhoto,
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text('Фото (${_photoUrls.length + _pendingPhotoBytes.length}/$_maxPhotos)'),
                ),
                for (var i = 0; i < _photoUrls.length; i++)
                  Chip(label: Text('Фото ${i + 1}', style: AppTypography.caption())),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _storeChip(String code, String label) {
    final selected = _storeLocation == code;
    final colors = storeLocationBadgeColors(code);
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _storeLocation = code),
      selectedColor: colors.bg,
      labelStyle: TextStyle(
        color: colors.fg,
        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
      ),
    );
  }

  Widget _buildMetalSection({
    required String title,
    required List<ScrapFinenessRow> rows,
    required double standardProbe,
    required String eqLabel,
    required TextEditingController stdRate,
    required TextEditingController tradeRate,
    required TextEditingController purchaseGrams,
    required ScrapPayoutBreakdown? breakdown,
    required VoidCallback onAddCustom,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: AppTypography.heading(fontSize: 16)),
            const SizedBox(height: 8),
            _finenessTable(rows, standardProbe, eqLabel),
            TextButton.icon(
              onPressed: onAddCustom,
              icon: const Icon(Icons.add),
              label: const Text('+ Другая проба'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: stdRate,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: standardProbe == 585
                    ? 'Стандартная цена за 1 г (585), ₩'
                    : 'Стандартная цена за 1 г (925), ₩',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: tradeRate,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: standardProbe == 585
                    ? 'Повышенная цена при покупке за 1 г (585), ₩'
                    : 'Повышенная цена при покупке за 1 г (925), ₩',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: purchaseGrams,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: standardProbe == 585
                    ? 'Вес покупаемого золотого изделия, г'
                    : 'Вес покупаемого серебряного изделия, г',
                border: const OutlineInputBorder(),
              ),
            ),
            if (breakdown != null) ...[
              const SizedBox(height: 12),
              Text(
                'Всего в ${standardProbe.toInt()} пробе: ${breakdown.totalEquivalent.toStringAsFixed(4)} г',
                style: AppTypography.productMeta(),
              ),
              Text(
                'Повышенный тариф: ${breakdown.tradeinPaidGrams.toStringAsFixed(4)} г · '
                'Стандарт: ${breakdown.standardPaidGrams.toStringAsFixed(4)} г',
                style: AppTypography.productMeta(),
              ),
              Text(
                'Сумма: ${formatWon(breakdown.payoutKrw)}',
                style: AppTypography.price(fontSize: 15),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _finenessTable(
    List<ScrapFinenessRow> rows,
    double standardProbe,
    String eqLabel,
  ) {
    return Table(
      columnWidths: const {
        0: FlexColumnWidth(1.2),
        1: FlexColumnWidth(1.2),
        2: FlexColumnWidth(1),
        3: FlexColumnWidth(1.4),
      },
      children: [
        TableRow(
          children: [
            _th('Проба'),
            _th('Вес, г'),
            _th('Камни, %'),
            _th('$eqLabel'),
          ],
        ),
        for (var i = 0; i < rows.length; i++)
          TableRow(
            children: [
              rows[i].customFineness
                  ? SizedBox(
                      width: 64,
                      child: TextFormField(
                        initialValue: rows[i].fineness.toStringAsFixed(0),
                        keyboardType: TextInputType.number,
                        onChanged: (v) {
                          rows[i].fineness = double.tryParse(v) ?? rows[i].fineness;
                        },
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text('${rows[i].fineness.toInt()}'),
                    ),
              _weightField(rows[i]),
              _stoneField(rows[i]),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  rows[i].grossWeight > 0
                      ? rows[i].equivalentToStandard(standardProbe).toStringAsFixed(4)
                      : '—',
                  style: AppTypography.caption(),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _th(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(text, style: AppTypography.caption(fontWeight: FontWeight.w700)),
      );

  Widget _weightField(ScrapFinenessRow row) => TextFormField(
        initialValue: row.grossWeight > 0 ? '${row.grossWeight}' : '',
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(isDense: true),
        onChanged: (v) => setState(() {
          row.grossWeight = double.tryParse(v.replaceAll(',', '.')) ?? 0;
        }),
      );

  Widget _stoneField(ScrapFinenessRow row) => TextFormField(
        initialValue: row.stoneDiscountPercent > 0
            ? '${row.stoneDiscountPercent}'
            : '',
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: const InputDecoration(isDense: true),
        onChanged: (v) => setState(() {
          row.stoneDiscountPercent = double.tryParse(v.replaceAll(',', '.')) ?? 0;
        }),
      );

  Widget _buildJournalTab() {
    final kpi = _journalKpi();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: _journalFilters(),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: _journalKpiBar(kpi),
        ),
        if (!widget.hideJournalBulkWriteOff)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _writeOffSelected,
                icon: const Icon(Icons.archive_outlined),
                label: const Text('Списать выбранные / со склада'),
              ),
            ),
          ),
        Expanded(
          child: _journalLoading
              ? const Center(child: CircularProgressIndicator())
              : _journal.isEmpty
                  ? Center(child: Text('Нет актов', style: AppTypography.productMeta()))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: _journal.length,
                      itemBuilder: (context, index) {
                        final row = _journal[index];
                        return _journalCard(row);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _journalFilters() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _filterChipGroup(
          'Магазин',
          [
            (null, 'Все'),
            (StoreLocationCode.icn, 'Инчхон'),
            (StoreLocationCode.ans, 'Ансан'),
          ],
          _filterStore,
          (v) => setState(() => _filterStore = v),
        ),
        _filterChipGroup(
          'Металл',
          [
            (null, 'Все'),
            ('gold', 'Золото'),
            ('silver', 'Серебро'),
          ],
          _filterMetal,
          (v) => setState(() => _filterMetal = v),
        ),
        _filterChipGroup(
          'Статус',
          [
            ('in_stock', 'На складе'),
            ('in_transfer', 'В трансфере'),
            ('written_off', 'Списано'),
            ('all', 'Все'),
          ],
          _filterStatus,
          (v) => setState(() => _filterStatus = v),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final range = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate: DateTime.now().add(const Duration(days: 1)),
            );
            if (range != null) {
              setState(() {
                _filterFrom = range.start;
                _filterTo = range.end;
              });
            }
          },
          icon: const Icon(Icons.date_range),
          label: Text(
            _filterFrom == null
                ? 'Период'
                : '${DateFormat('dd.MM.yy').format(_filterFrom!)} — '
                    '${_filterTo != null ? DateFormat('dd.MM.yy').format(_filterTo!) : '…'}',
          ),
        ),
        if (_filterFrom != null)
          IconButton(
            onPressed: () => setState(() {
              _filterFrom = null;
              _filterTo = null;
            }),
            icon: const Icon(Icons.clear),
          ),
        FilledButton(onPressed: _loadJournal, child: const Text('Применить')),
      ],
    );
  }

  Widget _filterChipGroup(
    String title,
    List<(String?, String)> options,
    String? current,
    ValueChanged<String?> onPick,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$title: ', style: AppTypography.caption()),
        ...options.map(
          (opt) => Padding(
            padding: const EdgeInsets.only(right: 4),
            child: ChoiceChip(
              label: Text(opt.$2),
              selected: current == opt.$1 || (opt.$1 == 'all' && current == 'all'),
              onSelected: (_) {
                onPick(opt.$1);
              },
            ),
          ),
        ),
      ],
    );
  }

  ({double goldG, int goldKrw, double silverG, int silverKrw, int total}) _journalKpi() {
    double goldG = 0;
    int goldKrw = 0;
    double silverG = 0;
    int silverKrw = 0;
    for (final row in _journal) {
      goldG += (row['gold_total_eq_585'] as num?)?.toDouble() ?? 0;
      goldKrw += (row['gold_payout_krw'] as num?)?.round() ?? 0;
      silverG += (row['silver_total_eq_925'] as num?)?.toDouble() ?? 0;
      silverKrw += (row['silver_payout_krw'] as num?)?.round() ?? 0;
    }
    return (
      goldG: goldG,
      goldKrw: goldKrw,
      silverG: silverG,
      silverKrw: silverKrw,
      total: goldKrw + silverKrw,
    );
  }

  Widget _journalKpiBar(
    ({double goldG, int goldKrw, double silverG, int silverKrw, int total}) kpi,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            Text('Золото: ${kpi.goldG.toStringAsFixed(2)} г · ${formatWon(kpi.goldKrw)}'),
            Text('Серебро: ${kpi.silverG.toStringAsFixed(2)} г · ${formatWon(kpi.silverKrw)}'),
            Text('Итого: ${formatWon(kpi.total)}', style: AppTypography.heading(fontSize: 16)),
          ],
        ),
      ),
    );
  }

  List<Widget> _formatItemsLines(
    dynamic raw,
    String prefix,
    String eqKey,
  ) {
    if (raw is! List) return [];
    return raw.whereType<Map>().map((item) {
      final f = item['fineness'];
      final gross = item['gross_weight'];
      final stone = item['stone_discount_percent'];
      final net = item['net_weight'];
      final eq = item[eqKey];
      return Padding(
        padding: const EdgeInsets.only(left: 8, bottom: 4),
        child: Text(
          '$prefix ${f}: вес $gross г, камни $stone %, чист. $net г, экв. $eq г',
          style: AppTypography.productMeta(),
        ),
      );
    }).toList();
  }

  Future<void> _startScrapTransfer(Map<String, dynamic> row) async {
    final id = row['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final from = row['store_location']?.toString().toUpperCase() ?? 'ICN';
    final to = from == 'ICN' ? 'ANS' : 'ICN';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отправить лом в трансфер?'),
        content: Text('Маршрут: $from → $to'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Отправить')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final result = await widget.database.initiateScrapTransfer(
      intakeId: id,
      toStore: to,
      senderCode: widget.actorCode,
    );
    if (result['ok'] != true) {
      _snack(result['error']?.toString() ?? 'Ошибка', error: true);
      return;
    }
    _snack('Лом отправлен в $to');
    await _loadJournal();
  }

  Future<void> _completeScrapTransfer(Map<String, dynamic> row) async {
    final id = row['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final result = await widget.database.completeScrapTransfer(
      intakeId: id,
      receiverCode: widget.actorCode,
    );
    if (result['ok'] != true) {
      _snack(result['error']?.toString() ?? 'Ошибка приёмки', error: true);
      return;
    }
    _snack('Лом принят на склад');
    await _loadJournal();
  }

  Future<void> _cancelScrapTransfer(Map<String, dynamic> row) async {
    final id = row['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Отменить трансфер лома?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Отменить')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final result = await widget.database.cancelScrapTransfer(intakeId: id);
    if (result['ok'] != true) {
      _snack(result['error']?.toString() ?? 'Не удалось отменить', error: true);
      return;
    }
    _snack('Трансфер отменён');
    await _loadJournal();
  }

  Widget _journalCard(Map<String, dynamic> row) {
    final id = row['id']?.toString() ?? '';
    final status = row['status']?.toString() ?? '';
    final inStock = status == 'in_stock';
    final inTransfer = status == 'in_transfer';
    final store = row['store_location']?.toString() ?? StoreLocationCode.icn;
    final transferTo = row['transfer_to_store']?.toString();
    final colors = storeLocationBadgeColors(store);
    final selected = _selectedJournalIds.contains(id);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Checkbox(
                  value: selected,
                  onChanged: inStock
                      ? (v) => setState(() {
                            if (v == true) {
                              _selectedJournalIds.add(id);
                            } else {
                              _selectedJournalIds.remove(id);
                            }
                          })
                      : null,
                ),
                Expanded(
                  child: Text(
                    _formatKst(row['created_at']),
                    style: AppTypography.caption(fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.bg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    storeLocationDisplayLabel(store),
                    style: TextStyle(color: colors.fg, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            Text(
              '${row['accepted_by_name']} · '
              '${inStock
                  ? 'На складе'
                  : inTransfer
                      ? 'В трансфере'
                      : 'Списано'}',
              style: AppTypography.productMeta(),
            ),
            if (inTransfer && transferTo != null)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'В пути: $store → $transferTo',
                  style: AppTypography.caption(fontWeight: FontWeight.w700),
                ),
              ),
            if ((row['notes']?.toString().trim() ?? '').isNotEmpty)
              Text(row['notes'].toString(), style: AppTypography.productMeta()),
            const SizedBox(height: 6),
            Text(
              'Выплата: ${formatWon((row['total_payout_krw'] as num?)?.round() ?? 0)}',
              style: AppTypography.price(fontSize: 14),
            ),
            Text(
              '585: ${((row['gold_total_eq_585'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)} г · '
              '925: ${((row['silver_total_eq_925'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)} г',
              style: AppTypography.productMeta(),
            ),
            ExpansionTile(
              title: Text('Детализация проб', style: AppTypography.caption()),
              children: [
                ..._formatItemsLines(row['gold_items'], 'Золото', 'equivalent_585_weight'),
                ..._formatItemsLines(row['silver_items'], 'Серебро', 'equivalent_925_weight'),
                Text(
                  'Тарифы золото: стандарт ${formatWon((row['gold_standard_rate_krw'] as num?)?.round() ?? 0)}/г · '
                  'повыш. ${formatWon((row['gold_tradein_rate_krw'] as num?)?.round() ?? 0)}/г',
                  style: AppTypography.productMeta(),
                ),
                Text(
                  'Тарифы серебро: стандарт ${formatWon((row['silver_standard_rate_krw'] as num?)?.round() ?? 0)}/г · '
                  'повыш. ${formatWon((row['silver_tradein_rate_krw'] as num?)?.round() ?? 0)}/г',
                  style: AppTypography.productMeta(),
                ),
              ],
            ),
            if (_parseUrlList(row['photo_urls']).isNotEmpty)
              SizedBox(
                height: 56,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: _parseUrlList(row['photo_urls'])
                      .map(
                        (url) => Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Image.network(url, width: 56, height: 56, fit: BoxFit.cover),
                        ),
                      )
                      .toList(),
                ),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => _loadActToForm(row),
                  child: const Text('Редактировать'),
                ),
                if (inStock)
                  FilledButton.tonal(
                    onPressed: () => _startScrapTransfer(row),
                    child: const Text('В трансфер'),
                  ),
                if (inStock)
                  OutlinedButton(
                    onPressed: () async {
                      final res = await widget.database.writeOffScrapMetalIntakes(ids: [id]);
                      if (!res.ok) {
                        _snack(res.error ?? 'Ошибка', error: true);
                        return;
                      }
                      _snack('Списано со склада');
                      await _loadJournal();
                    },
                    child: const Text('Списать со склада'),
                  ),
                if (inTransfer) ...[
                  FilledButton(
                    onPressed: () => _completeScrapTransfer(row),
                    child: const Text('Принять лом'),
                  ),
                  OutlinedButton(
                    onPressed: () => _cancelScrapTransfer(row),
                    child: const Text('Отменить'),
                  ),
                ],
                TextButton(
                  onPressed: () => _deleteAct(id),
                  child: const Text('Удалить', style: TextStyle(color: AppColors.saleRed)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}