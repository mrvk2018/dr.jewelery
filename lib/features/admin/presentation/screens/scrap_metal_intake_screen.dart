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
import '../../domain/trade_in_scrap_draft.dart';
import '../widgets/admin_toast.dart';
import '../widgets/scrap_ledger_ui.dart';
import 'scrap_ledger_screen.dart';

/// Приёмка лома: расчёт 585/925, журнал, списание со склада.
class ScrapMetalIntakeScreen extends StatefulWidget {
  ScrapMetalIntakeScreen({
    super.key,
    DatabaseService? database,
    this.initialSellerCode,
    this.initialSellerName,
    this.hideJournalBulkWriteOff = false,
    this.actorCode = 'ADMIN',
    this.tradeInMode = false,
    this.cartTotalAmountKrw,
    this.initialPurchasedGoldWeightG,
    this.initialStoreLocation,
    this.initialTradeInDraft,
    this.onCancelToDashboard,
  }) : database = database ?? DatabaseService.create();

  final DatabaseService database;
  final String? initialSellerCode;
  final String? initialSellerName;
  final bool hideJournalBulkWriteOff;
  final String actorCode;

  /// POS Trade-In: без записи в БД, возврат [TradeInScrapDraft].
  final bool tradeInMode;
  final int? cartTotalAmountKrw;
  final double? initialPurchasedGoldWeightG;
  final String? initialStoreLocation;
  final TradeInScrapDraft? initialTradeInDraft;

  /// Вкладка в [AdminWebShell]: сброс формы и переход на «Рабочий стол».
  final VoidCallback? onCancelToDashboard;

  @override
  State<ScrapMetalIntakeScreen> createState() => _ScrapMetalIntakeScreenState();
}

class _ScrapMetalIntakeScreenState extends State<ScrapMetalIntakeScreen>
    with SingleTickerProviderStateMixin {
  static const _adminAcceptKey = 'ADMIN';
  static const _maxPhotos = 2;
  static const _wideLayoutMinWidth = 760.0;

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

  /// Секция серебра на вкладке «Приёмка и расчёт» свёрнута по умолчанию.
  bool _isSilverExpanded = false;

  /// Сброс `TextFormField(initialValue)` после восстановления черновика / акта.
  int _finenessInputsEpoch = 0;

  final ScrollController _intakeScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    final tabCount = widget.tradeInMode ? 1 : 3;
    _tabs = TabController(length: tabCount, vsync: this);
    if (!widget.tradeInMode) {
      _tabs.addListener(() {
        if (_tabs.indexIsChanging) return;
        if (_tabs.index == 1) _loadJournal();
      });
    }
    if (widget.initialSellerCode != null &&
        widget.initialSellerName != null) {
      _acceptKey = widget.initialSellerCode!;
    }
    if (widget.initialStoreLocation != null) {
      _storeLocation = widget.initialStoreLocation!.trim().toUpperCase();
    }
    if (widget.initialPurchasedGoldWeightG != null &&
        widget.initialPurchasedGoldWeightG! > 0) {
      _goldPurchaseGrams.text =
          widget.initialPurchasedGoldWeightG!.toStringAsFixed(2);
    }
    _bootstrap().then((_) {
      if (!mounted) return;
      final seed = widget.initialTradeInDraft;
      if (seed != null) _applyTradeInDraft(seed);
    });
  }

  @override
  void dispose() {
    _intakeScrollController.dispose();
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

  static const _standardGoldFineness = <int>[375, 585, 750, 995];
  static const _standardSilverFineness = <int>[875, 925, 999];

  static String _formatDecimalField(double value, {bool allowZero = false}) {
    if (value <= 0 && !allowZero) return '';
    if (value == 0 && allowZero) return '0';
    final fixed = value.toStringAsFixed(2);
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  Future<void> _bootstrap() async {
    final restoringTradeIn =
        widget.tradeInMode && widget.initialTradeInDraft != null;
    try {
      final storage = await ScrapMetalStorage.create();
      if (!mounted) return;
      if (!restoringTradeIn) {
        setState(() => _storeLocation = storage.storeLocation);
        _goldStdRate.text = '${storage.goldStandardRateKrw}';
        _goldTradeRate.text = '${storage.goldTradeinRateKrw}';
        _silverStdRate.text = '${storage.silverStandardRateKrw}';
        _silverTradeRate.text = '${storage.silverTradeinRateKrw}';
      }
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
    showAdminToast(context, msg, error: error);
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

  int get _scrapTotalKrw {
    final g = _goldBreakdown?.payoutKrw ?? 0;
    final s = _silverBreakdown?.payoutKrw ?? 0;
    return ScrapMetalCalculator.floorKrwTo1000(g + s);
  }

  int? get _tradeInNetDelta {
    final cart = widget.cartTotalAmountKrw;
    if (cart == null || !widget.tradeInMode) return null;
    return cart - _scrapTotalKrw;
  }

  void _applyTradeInDraft(TradeInScrapDraft draft) {
    final payload = draft.scrapPayload;
    final loc = payload['store_location']?.toString().trim().toUpperCase();
    _storeLocation = loc == 'ANS' ? StoreLocationCode.ans : StoreLocationCode.icn;
    final code = payload['accepted_by_code']?.toString();
    if (code != null && code.isNotEmpty) {
      _acceptKey = code == 'ADMIN' ? _adminAcceptKey : code;
    }
    _notesController.text = payload['notes']?.toString() ?? '';
    _goldStdRate.text = '${payload['gold_standard_rate_krw'] ?? ''}';
    _goldTradeRate.text = '${payload['gold_tradein_rate_krw'] ?? ''}';
    final goldPurchase = (payload['gold_purchase_offset_grams'] as num?)
            ?.toDouble() ??
        draft.cartGoldWeightGrams;
    _goldPurchaseGrams.text = _formatDecimalField(goldPurchase, allowZero: true);
    _silverStdRate.text = '${payload['silver_standard_rate_krw'] ?? ''}';
    _silverTradeRate.text = '${payload['silver_tradein_rate_krw'] ?? ''}';
    final silverPurchase =
        (payload['silver_purchase_offset_grams'] as num?)?.toDouble() ?? 0;
    _silverPurchaseGrams.text =
        _formatDecimalField(silverPurchase, allowZero: true);
    _goldRows
      ..clear()
      ..addAll(_rowsFromJson(payload['gold_items'], isGold: true));
    _silverRows
      ..clear()
      ..addAll(_rowsFromJson(payload['silver_items'], isGold: false));
    _isSilverExpanded = ScrapFinenessRow.activeRows(_silverRows).isNotEmpty;
    _finenessInputsEpoch++;
    _photoUrls
      ..clear()
      ..addAll(_parseUrlList(payload['photo_urls']));
    _pendingPhotoBytes.clear();
    _runCalculate();
    if (mounted) setState(() {});
  }

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
      final total = ScrapMetalCalculator.floorKrwTo1000(
        gold.payoutKrw + silver.payoutKrw,
      );
      _highlightPayout = 'Итого: ${formatWon(total)}';
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

      if (widget.tradeInMode) {
        final cartTotal = widget.cartTotalAmountKrw ?? 0;
        final scrapTotal = _scrapTotalKrw;
        final net = cartTotal - scrapTotal;
        final goldEq = ScrapMetalCalculator.sumGoldEquivalent(_goldRows);
        if (!mounted) return;
        Navigator.of(context).pop(
          TradeInScrapDraft(
            scrapPayload: payload,
            scrapTotalKrw: scrapTotal,
            cartTotalKrw: cartTotal,
            cartGoldWeightGrams: _parseDouble(_goldPurchaseGrams),
            netCashDeltaKrw: net,
            goldEquivalent585: goldEq,
            storeLocation: _storeLocation,
          ),
        );
        return;
      }

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
    _goldPurchaseGrams.text = '0';
    _silverPurchaseGrams.text = '0';
    _photoUrls.clear();
    _pendingPhotoBytes.clear();
    _calculated = false;
    _goldBreakdown = null;
    _silverBreakdown = null;
    _highlightPayout = null;
    _isSilverExpanded = false;
    _acceptKey = widget.initialSellerCode ?? _adminAcceptKey;
    if (!keepRates) {
      _goldStdRate.clear();
      _goldTradeRate.clear();
      _silverStdRate.clear();
      _silverTradeRate.clear();
    }
    _finenessInputsEpoch++;
  }

  Future<void> _cancelToDashboard() async {
    final go = widget.onCancelToDashboard;
    if (go == null) return;

    setState(() {
      _editingId = null;
      _resetIntakeForm(keepRates: false);
      _acceptKey = widget.initialSellerCode ?? _adminAcceptKey;
      final initialLoc = widget.initialStoreLocation?.trim().toUpperCase();
      if (initialLoc != null && initialLoc.isNotEmpty) {
        _storeLocation = initialLoc;
      } else {
        _storeLocation = StoreLocationCode.icn;
      }
    });

    try {
      final storage = await ScrapMetalStorage.create();
      if (mounted) {
        setState(() {
          _storeLocation = storage.storeLocation;
          _goldStdRate.text = '${storage.goldStandardRateKrw}';
          _goldTradeRate.text = '${storage.goldTradeinRateKrw}';
          _silverStdRate.text = '${storage.silverStandardRateKrw}';
          _silverTradeRate.text = '${storage.silverTradeinRateKrw}';
        });
      }
    } catch (_) {}

    if (!mounted) return;
    if (!widget.tradeInMode && _tabs.index != 0) {
      _tabs.animateTo(0);
    }
    go();
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
      _isSilverExpanded = ScrapFinenessRow.activeRows(_silverRows).isNotEmpty;
      _finenessInputsEpoch++;
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
    final defaults = isGold ? _defaultGoldRows() : _defaultSilverRows();
    final standards =
        isGold ? _standardGoldFineness : _standardSilverFineness;
    if (raw is! List || raw.isEmpty) {
      return defaults;
    }

    final byStandardFineness = <int, ScrapFinenessRow>{
      for (final row in defaults) row.fineness.round(): row,
    };
    final customRows = <ScrapFinenessRow>[];

    for (final item in raw) {
      if (item is! Map) continue;
      final fineness = (item['fineness'] as num?)?.toDouble() ?? 0;
      if (fineness <= 0) continue;
      final gross = (item['gross_weight'] as num?)?.toDouble() ?? 0;
      final stone = (item['stone_discount_percent'] as num?)?.toDouble() ?? 0;
      final key = fineness.round();

      if (standards.contains(key)) {
        final row = byStandardFineness[key];
        if (row != null) {
          row.grossWeight = gross;
          row.stoneDiscountPercent = stone;
          continue;
        }
      }

      customRows.add(
        ScrapFinenessRow(
          fineness: fineness,
          grossWeight: gross,
          stoneDiscountPercent: stone,
          customFineness: true,
        ),
      );
    }

    return [...defaults, ...customRows];
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
    final tradeIn = widget.tradeInMode;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: widget.onCancelToDashboard == null,
        leading: widget.onCancelToDashboard != null
            ? const SizedBox.shrink()
            : null,
        title: Text(
          tradeIn ? 'Приёмка лома (Trade-In)' : 'Приёмка лома',
          style: AppTypography.heading(fontSize: 20),
        ),
        actions: tradeIn
            ? null
            : [
                IconButton(
                  tooltip: 'Учёт и списание лома',
                  onPressed: () => ScrapLedgerScreen.open(
                    context,
                    database: widget.database,
                    sellerCode:
                        widget.actorCode == 'ADMIN' ? null : widget.actorCode,
                    initialBranch: _storeLocation,
                  ),
                  icon: const Icon(Icons.inventory_2_outlined),
                ),
              ],
        bottom: tradeIn
            ? null
            : TabBar(
                controller: _tabs,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: const [
                  Tab(text: 'Приёмка и расчёт'),
                  Tab(text: 'Журнал актов'),
                  Tab(text: 'Учёт / Списание'),
                ],
              ),
      ),
      body: tradeIn
          ? _buildIntakeTab()
          : TabBarView(
              controller: _tabs,
              children: [
                _buildIntakeTab(),
                _buildJournalTab(),
                ScrapLedgerPanel(
                  database: widget.database,
                  sellerCode:
                      widget.actorCode == 'ADMIN' ? null : widget.actorCode,
                  initialBranch: _storeLocation,
                  embedded: true,
                ),
              ],
            ),
    );
  }

  bool _isWideLayout(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= _wideLayoutMinWidth;

  InputDecoration _scrapCompactFieldDecoration(String labelText) =>
      InputDecoration(
        labelText: labelText,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: const OutlineInputBorder(),
      );

  Widget _buildIntakeTab() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = _isWideLayout(context);
        final sectionGap = wide ? 8.0 : 16.0;
        final outerPad = wide ? 12.0 : 16.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Scrollbar(
                controller: _intakeScrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _intakeScrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    outerPad,
                    outerPad,
                    outerPad,
                    wide ? 8 : 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildHeaderCard(wide),
                      SizedBox(height: sectionGap),
                      _buildMetalSection(
                        wide: wide,
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
                            ScrapFinenessRow(
                              fineness: 583,
                              customFineness: true,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(height: sectionGap),
                      _buildMetalSection(
                        wide: wide,
                        title: 'Серебро (приведение к 925 пробе)',
                        rows: _silverRows,
                        standardProbe: 925,
                        eqLabel: 'В 925 пробе',
                        stdRate: _silverStdRate,
                        tradeRate: _silverTradeRate,
                        purchaseGrams: _silverPurchaseGrams,
                        breakdown: _silverBreakdown,
                        collapsible: true,
                        expanded: _isSilverExpanded,
                        onToggleExpanded: () => setState(
                          () => _isSilverExpanded = !_isSilverExpanded,
                        ),
                        summaryBadge: _silverSectionSummaryBadge(),
                        onAddCustom: () => setState(
                          () => _silverRows.add(
                            ScrapFinenessRow(
                              fineness: 800,
                              customFineness: true,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            _buildIntakeFooterBar(wide),
          ],
        );
      },
    );
  }

  Widget _buildIntakeFooterBar(bool wide) {
    return Material(
      elevation: 6,
      color: AppColors.cardBackground,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            wide ? 12 : 16,
            wide ? 8 : 10,
            wide ? 12 : 16,
            wide ? 8 : 10,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_highlightPayout != null)
                Padding(
                  padding: EdgeInsets.only(bottom: wide ? 6 : 8),
                  child: Card(
                    margin: EdgeInsets.zero,
                    color: AppColors.accent.withValues(alpha: 0.12),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: wide ? 10 : 12,
                        vertical: wide ? 8 : 10,
                      ),
                      child: Text(
                        _highlightPayout!,
                        style: AppTypography.heading(fontSize: wide ? 16 : 18),
                      ),
                    ),
                  ),
                ),
              if (widget.tradeInMode && _calculated && _tradeInNetDelta != null)
                Padding(
                  padding: EdgeInsets.only(bottom: wide ? 6 : 8),
                  child: _TradeInDeltaBanner(netDeltaKrw: _tradeInNetDelta!),
                ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (widget.onCancelToDashboard != null)
                    OutlinedButton(
                      onPressed: _cancelToDashboard,
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      child: const Text('Отмена'),
                    ),
                  OutlinedButton(
                    onPressed: _runCalculate,
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                    ),
                    child: const Text('Рассчитать'),
                  ),
                  FilledButton(
                    onPressed: _saving ? null : _saveIntake,
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Принять'),
                  ),
                  if (_editingId != null)
                    TextButton(
                      onPressed: () => setState(() {
                        _editingId = null;
                        _resetIntakeForm();
                      }),
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Отменить редактирование'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(bool wide) {
    final cardPad = wide ? 10.0 : 12.0;
    final acceptDropdown = DropdownButtonFormField<String>(
      initialValue: _acceptKey,
      isDense: wide,
      decoration: _scrapCompactFieldDecoration('Кто принял'),
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
      onChanged: _loadingSellers
          ? null
          : (v) => setState(() => _acceptKey = v ?? _adminAcceptKey),
    );

    final photoButton = OutlinedButton.icon(
      onPressed: _pickPhoto,
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      ),
      icon: const Icon(Icons.photo_camera_outlined, size: 18),
      label: Text(
        'Фото (${_photoUrls.length + _pendingPhotoBytes.length}/$_maxPhotos)',
        style: AppTypography.productMeta(),
      ),
    );

    if (wide) {
      return Card(
        child: Padding(
          padding: EdgeInsets.all(cardPad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Магазин',
                        style: AppTypography.productMeta()
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _storeChip(StoreLocationCode.icn, 'Инчхон'),
                          const SizedBox(width: 8),
                          _storeChip(StoreLocationCode.ans, 'Ансан'),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: acceptDropdown),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _notesController,
                      maxLines: 1,
                      decoration:
                          _scrapCompactFieldDecoration('Комментарий / клиент'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  photoButton,
                ],
              ),
              if (_photoUrls.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (var i = 0; i < _photoUrls.length; i++)
                      Chip(
                        visualDensity: VisualDensity.compact,
                        label: Text(
                          'Фото ${i + 1}',
                          style: AppTypography.caption(),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: EdgeInsets.all(cardPad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Магазин',
              style:
                  AppTypography.productMeta().copyWith(fontWeight: FontWeight.w700),
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
            acceptDropdown,
            const SizedBox(height: 8),
            TextField(
              controller: _notesController,
              decoration: _scrapCompactFieldDecoration('Комментарий / клиент'),
              maxLines: 2,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                photoButton,
                for (var i = 0; i < _photoUrls.length; i++)
                  Chip(
                    label: Text('Фото ${i + 1}', style: AppTypography.caption()),
                  ),
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
      label: Text(label, style: const TextStyle(fontSize: 13)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      selected: selected,
      onSelected: (_) => setState(() => _storeLocation = code),
      selectedColor: colors.bg,
      labelStyle: TextStyle(
        color: colors.fg,
        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
      ),
    );
  }

  String? _silverSectionSummaryBadge() {
    final hasWeight = _silverRows.any((r) => r.grossWeight > 0);
    final purchase =
        double.tryParse(_silverPurchaseGrams.text.replaceAll(',', '.')) ?? 0;
    if (!hasWeight && purchase <= 0 && _silverBreakdown == null) {
      return null;
    }
    if (_silverBreakdown != null) {
      final eq = _silverBreakdown!.totalEquivalent.toStringAsFixed(2);
      return '$eq г · ${formatWon(_silverBreakdown!.payoutKrw)}';
    }
    final eq = ScrapMetalCalculator.sumSilverEquivalent(_silverRows);
    if (eq > 0) return '${eq.toStringAsFixed(2)} г в 925';
    if (purchase > 0) return 'покупка ${purchase.toStringAsFixed(2)} г';
    return null;
  }

  Widget _buildMetalSection({
    required bool wide,
    required String title,
    required List<ScrapFinenessRow> rows,
    required double standardProbe,
    required String eqLabel,
    required TextEditingController stdRate,
    required TextEditingController tradeRate,
    required TextEditingController purchaseGrams,
    required ScrapPayoutBreakdown? breakdown,
    required VoidCallback onAddCustom,
    bool collapsible = false,
    bool expanded = true,
    VoidCallback? onToggleExpanded,
    String? summaryBadge,
  }) {
    final stdLabel = standardProbe == 585
        ? 'Стандартная цена за 1 г (585), ₩'
        : 'Стандартная цена за 1 г (925), ₩';
    final tradeLabel = standardProbe == 585
        ? 'Повышенная цена при покупке за 1 г (585), ₩'
        : 'Повышенная цена при покупке за 1 г (925), ₩';
    final purchaseLabel = standardProbe == 585
        ? 'Вес покупаемого золотого изделия, г'
        : 'Вес покупаемого серебряного изделия, г';

    final stdField = TextField(
      controller: stdRate,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: _scrapCompactFieldDecoration(stdLabel),
    );
    final tradeField = TextField(
      controller: tradeRate,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: _scrapCompactFieldDecoration(tradeLabel),
    );
    final purchaseField = TextField(
      controller: purchaseGrams,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: _scrapCompactFieldDecoration(purchaseLabel),
    );

    final rateFields = wide
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: stdField),
              const SizedBox(width: 10),
              Expanded(child: tradeField),
              const SizedBox(width: 10),
              Expanded(child: purchaseField),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              stdField,
              const SizedBox(height: 8),
              tradeField,
              const SizedBox(height: 8),
              purchaseField,
            ],
          );

  final cardPad = wide ? 10.0 : 12.0;
  final titleSize = wide ? 15.0 : 16.0;
  final sectionBody = <Widget>[
      _finenessTable(rows, standardProbe, eqLabel, compact: wide),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: onAddCustom,
          style: TextButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('+ Другая проба'),
        ),
      ),
      SizedBox(height: wide ? 6 : 8),
      rateFields,
      if (breakdown != null) ...[
        SizedBox(height: wide ? 8 : 12),
        Text(
          'Всего в ${standardProbe.toInt()} пробе: ${formatScrapGrams(breakdown.totalEquivalent)}',
          style: AppTypography.productMeta().copyWith(fontSize: wide ? 12 : null),
        ),
        Text(
          'Повышенный тариф: ${formatScrapGrams(breakdown.tradeinPaidGrams)} · '
          'Стандарт: ${formatScrapGrams(breakdown.standardPaidGrams)}',
          style: AppTypography.productMeta().copyWith(fontSize: wide ? 12 : null),
        ),
        Text(
          'Сумма: ${formatWon(breakdown.payoutKrw)}',
          style: AppTypography.price(fontSize: wide ? 14 : 15),
        ),
      ],
    ];

    Widget titleWidget;
    if (collapsible) {
      titleWidget = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onToggleExpanded,
          borderRadius: BorderRadius.circular(8),
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          title,
                          style: AppTypography.heading(fontSize: titleSize),
                        ),
                        if (summaryBadge != null && summaryBadge.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.cardBackground,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Text(
                              summaryBadge,
                              style: AppTypography.productMeta().copyWith(
                                fontSize: 11,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(Icons.keyboard_arrow_down, size: 28),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    } else {
      titleWidget = Text(title, style: AppTypography.heading(fontSize: titleSize));
    }

    return Card(
      child: Padding(
        padding: EdgeInsets.all(cardPad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            titleWidget,
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(height: wide ? 6 : 8),
                  ...sectionBody,
                ],
              ),
              crossFadeState: (!collapsible || expanded)
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
              sizeCurve: Curves.easeInOut,
            ),
          ],
        ),
      ),
    );
  }

  Widget _finenessTable(
    List<ScrapFinenessRow> rows,
    double standardProbe,
    String eqLabel, {
    bool compact = false,
  }) {
    final rowPad = compact ? 2.0 : 8.0;
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
            _th('Проба', compact: compact),
            _th('Вес, г', compact: compact),
            _th('Камни, %', compact: compact),
            _th(eqLabel, compact: compact),
          ],
        ),
        for (var i = 0; i < rows.length; i++)
          TableRow(
            children: [
              rows[i].customFineness
                  ? SizedBox(
                      width: 64,
                      child: TextFormField(
                        key: ValueKey(
                          'fineness-${rows[i].fineness}-$i-$_finenessInputsEpoch',
                        ),
                        initialValue: rows[i].fineness.toStringAsFixed(0),
                        keyboardType: TextInputType.number,
                        onChanged: (v) {
                          rows[i].fineness = double.tryParse(v) ?? rows[i].fineness;
                        },
                      ),
                    )
                  : Padding(
                      padding: EdgeInsets.symmetric(vertical: rowPad),
                      child: Text('${rows[i].fineness.toInt()}'),
                    ),
              _weightField(rows[i], compact: compact),
              _stoneField(rows[i], compact: compact),
              Padding(
                padding: EdgeInsets.symmetric(vertical: rowPad),
                child: Text(
                  rows[i].grossWeight > 0
                      ? rows[i]
                          .equivalentToStandard(standardProbe)
                          .toStringAsFixed(2)
                      : '—',
                  style: AppTypography.caption(),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _th(String text, {bool compact = false}) => Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 1 : 4),
        child: Text(
          text,
          style: AppTypography.caption(fontWeight: FontWeight.w700).copyWith(
            fontSize: compact ? 11 : null,
          ),
        ),
      );

  Widget _weightField(ScrapFinenessRow row, {bool compact = false}) =>
      TextFormField(
        key: ValueKey(
          'weight-${row.fineness}-${row.customFineness}-$_finenessInputsEpoch',
        ),
        initialValue: _formatDecimalField(row.grossWeight),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(
            horizontal: 8,
            vertical: compact ? 4 : 6,
          ),
        ),
        onChanged: (v) => setState(() {
          row.grossWeight = double.tryParse(v.replaceAll(',', '.')) ?? 0;
        }),
      );

  Widget _stoneField(ScrapFinenessRow row, {bool compact = false}) =>
      TextFormField(
        key: ValueKey(
          'stone-${row.fineness}-${row.customFineness}-$_finenessInputsEpoch',
        ),
        initialValue: _formatDecimalField(row.stoneDiscountPercent),
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(
            horizontal: 8,
            vertical: compact ? 4 : 6,
          ),
        ),
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
              '585: ${formatScrapGrams((row['gold_total_eq_585'] as num?)?.toDouble() ?? 0)} · '
              '925: ${formatScrapGrams((row['silver_total_eq_925'] as num?)?.toDouble() ?? 0)}',
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

class _TradeInDeltaBanner extends StatelessWidget {
  const _TradeInDeltaBanner({required this.netDeltaKrw});

  final int netDeltaKrw;

  @override
  Widget build(BuildContext context) {
    final String badge;
    final Color bg;
    final Color fg;
    final String amount;
    if (netDeltaKrw > 0) {
      badge = 'Получить оплату от покупателя';
      bg = const Color(0xFFE8F5E9);
      fg = const Color(0xFF1B5E20);
      amount = '+${formatWon(netDeltaKrw)}';
    } else if (netDeltaKrw < 0) {
      badge = 'Доплатить покупателю';
      bg = const Color(0xFFFFEBEE);
      fg = AppColors.saleRed;
      amount = '−${formatWon(netDeltaKrw.abs())}';
    } else {
      badge = 'Обмен без доплаты';
      bg = AppColors.cardBackground;
      fg = AppColors.textSecondary;
      amount = formatWon(0);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Card(
        color: bg,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                amount,
                style: AppTypography.heading(fontSize: 22).copyWith(color: fg),
              ),
              const SizedBox(height: 6),
              Chip(
                label: Text(badge, style: TextStyle(color: fg, fontSize: 12)),
                backgroundColor: Colors.transparent,
                side: BorderSide(color: fg.withValues(alpha: 0.45)),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
      ),
    );
  }
}