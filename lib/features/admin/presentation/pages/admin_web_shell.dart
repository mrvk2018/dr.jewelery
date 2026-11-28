import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/admin/admin_access.dart';
import '../../../../core/admin/admin_staff_session_store.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/providers/profile_scope.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/services/database_service.dart';
import '../../../../screens/sales_history_screen.dart';
import '../screens/draft_intake_screen.dart';
import '../screens/product_transfers_screen.dart';
import '../screens/scrap_metal_intake_screen.dart';
import '../screens/staff_management_screen.dart';
import '../../../seller/presentation/screens/seller_my_payroll_screen.dart';
import '../../../seller/presentation/screens/seller_terminal_screen.dart';
import '../../application/inventory_active_session_counter.dart';
import '../../application/product_transfers_in_transit_counter.dart';
import '../widgets/admin_nav_count_badge.dart';
import '../../../../screens/inventory_revision_screen.dart';
import 'jewelry_admin_dashboard.dart';

/// Web-админка: супер-админ или режим продавца (смена после пасхалки).
class AdminWebShell extends StatefulWidget {
  const AdminWebShell({super.key});

  @override
  State<AdminWebShell> createState() => _AdminWebShellState();
}

class _AdminWebShellState extends State<AdminWebShell> {
  static const _salesHistoryTabIndex = 3;
  static const _sellerSalesHistoryTabIndex = 3;
  static const _revisionNavLabel = 'Ревизия';

  int _selectedIndex = 0;
  final _dashboardKey = GlobalKey<JewelryAdminDashboardState>();
  final _salesHistoryKey = GlobalKey<SalesHistoryScreenState>();
  late final DatabaseService _database = DatabaseService.create();
  late final ProductTransfersInTransitCounter _transfersInTransitCounter;
  late final InventoryActiveSessionCounter _inventoryActiveCounter;

  AdminStaffSession? _staffSession;
  bool _sessionReady = false;

  @override
  void initState() {
    super.initState();
    _transfersInTransitCounter = ProductTransfersInTransitCounter(_database);
    _transfersInTransitCounter.start();
    _inventoryActiveCounter = InventoryActiveSessionCounter(_database);
    _inventoryActiveCounter.start();
    _loadStaffSession();
  }

  @override
  void dispose() {
    _transfersInTransitCounter.dispose();
    _inventoryActiveCounter.dispose();
    super.dispose();
  }

  void _refreshTransfersBadge() {
    _transfersInTransitCounter.refresh();
  }

  Future<void> _loadStaffSession() async {
    final session = await AdminStaffSessionStore.readActiveSession();
    if (!mounted) return;
    setState(() {
      _staffSession = session;
      _sessionReady = true;
    });
  }

  bool _isSellerStaffMode(bool isSuperAdmin) =>
      !isSuperAdmin && _staffSession != null;

  List<({IconData icon, IconData selectedIcon, String label})> _adminDestinations(
    bool isSuperAdmin,
  ) =>
      [
        (
          icon: Icons.dashboard_outlined,
          selectedIcon: Icons.dashboard,
          label: 'Рабочий стол',
        ),
        (
          icon: Icons.local_shipping_outlined,
          selectedIcon: Icons.local_shipping,
          label: 'Трансферы',
        ),
        (
          icon: Icons.fact_check_outlined,
          selectedIcon: Icons.fact_check,
          label: _revisionNavLabel,
        ),
        (
          icon: Icons.history_edu_outlined,
          selectedIcon: Icons.history_edu,
          label: 'История продаж',
        ),
        if (isSuperAdmin)
          (
            icon: Icons.badge_outlined,
            selectedIcon: Icons.badge,
            label: 'Управление персоналом',
          ),
        if (isSuperAdmin)
          (
            icon: Icons.scale_outlined,
            selectedIcon: Icons.scale,
            label: 'Приёмка лома',
          ),
        (
          icon: Icons.logout_outlined,
          selectedIcon: Icons.logout,
          label: 'Выйти из админки',
        ),
      ];

  List<({IconData icon, IconData selectedIcon, String label})>
      _sellerDestinations() => [
            (
              icon: Icons.point_of_sale_outlined,
              selectedIcon: Icons.point_of_sale,
              label: 'Витрина / Касса',
            ),
            (
              icon: Icons.payments_outlined,
              selectedIcon: Icons.account_balance_wallet,
              label: 'Моя зарплата',
            ),
            (
              icon: Icons.scale_outlined,
              selectedIcon: Icons.scale,
              label: 'Приёмка лома',
            ),
            (
              icon: Icons.history_edu_outlined,
              selectedIcon: Icons.history_edu,
              label: 'История продаж',
            ),
            (
              icon: Icons.local_shipping_outlined,
              selectedIcon: Icons.local_shipping,
              label: 'Трансферы',
            ),
            (
              icon: Icons.fact_check_outlined,
              selectedIcon: Icons.fact_check,
              label: _revisionNavLabel,
            ),
            (
              icon: Icons.move_to_inbox_outlined,
              selectedIcon: Icons.move_to_inbox,
              label: 'Черновики',
            ),
          ];

  String _title({
    required bool isSuperAdmin,
    required bool sellerMode,
    required int index,
    required int destCount,
  }) {
    final safe = index.clamp(0, destCount - 1);
    if (sellerMode) {
      return switch (safe) {
        0 => 'Касса · витрина',
        1 => 'Моя зарплата и продажи',
        2 => 'Приёмка и журнал лома',
        3 => 'История продаж · KST / KRW',
        4 => 'Трансферы ICN ↔ ANS',
        5 => 'Ревизия витрин',
        6 => 'Приёмка черновиков',
        _ => 'Смена продавца',
      };
    }
    return switch (safe) {
      0 => 'Доктор Ювелирка · Рабочий стол',
      1 => 'Трансферы ICN ↔ ANS',
      2 => 'Ревизия витрин',
      3 => 'История продаж · KST / KRW',
      4 when isSuperAdmin => 'Управление персоналом',
      5 when isSuperAdmin => 'Приёмка лома',
      _ => 'Доктор Ювелирка',
    };
  }

  void _scheduleSalesHistoryReload() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _salesHistoryKey.currentState?.reload();
    });
  }

  void _scheduleCatalogRefreshAfterReturn() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _dashboardKey.currentState?.refreshCatalog();
    });
  }

  String _panelActorCode(AdminStaffSession? session) =>
      session?.promoCode ?? 'ADMIN';

  List<Widget> _adminPages(bool isSuperAdmin, AdminStaffSession? session) => [
        JewelryAdminDashboard(
          key: _dashboardKey,
          onPosSaleArchived: _scheduleSalesHistoryReload,
          onProductTransfersChanged: _refreshTransfersBadge,
        ),
        ProductTransfersScreen(
          actorCode: _panelActorCode(session),
          onTransfersMutated: _refreshTransfersBadge,
        ),
        InventoryRevisionScreen(
          database: _database,
          scannerDisplayName:
              session?.name ?? (isSuperAdmin ? 'Админ' : 'Сотрудник'),
        ),
        SalesHistoryScreen(
          key: _salesHistoryKey,
          onProductReturned: _scheduleCatalogRefreshAfterReturn,
        ),
        if (isSuperAdmin) StaffManagementScreen(database: _database),
        if (isSuperAdmin)
          ScrapMetalIntakeScreen(
            database: _database,
            actorCode: _panelActorCode(session),
            onCancelToDashboard: () => setState(() => _selectedIndex = 0),
          ),
      ];

  List<Widget> _sellerPages(AdminStaffSession session) => [
        JewelryAdminDashboard(
          key: _dashboardKey,
          sellerStaffMode: true,
          presetSellerPromoCode: session.promoCode,
          presetSellerName: session.name,
          onPosSaleArchived: _scheduleSalesHistoryReload,
          onProductTransfersChanged: _refreshTransfersBadge,
        ),
        SellerMyPayrollScreen(
          promoCode: session.promoCode,
          sellerName: session.name,
          database: _database,
        ),
        ScrapMetalIntakeScreen(
          database: _database,
          initialSellerCode: session.promoCode,
          initialSellerName: session.name,
          actorCode: session.promoCode,
          onCancelToDashboard: () => setState(() => _selectedIndex = 0),
        ),
        SalesHistoryScreen(
          key: _salesHistoryKey,
          onProductReturned: _scheduleCatalogRefreshAfterReturn,
        ),
        ProductTransfersScreen(
          actorCode: session.promoCode,
          onTransfersMutated: _refreshTransfersBadge,
        ),
        InventoryRevisionScreen(
          database: _database,
          scannerDisplayName: session.name,
        ),
        DraftIntakeScreen(
          database: _database,
          sellerStaffMode: true,
          actorCode: session.promoCode,
          onTransfersMutated: _refreshTransfersBadge,
        ),
      ];

  Future<void> _endSellerShift() async {
    await AdminStaffSessionStore.clearActiveSession();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _exitAdminPanel() {
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  static const _exitAdminNavLabel = 'Выйти из админки';

  bool _isExitAdminRailIndex(int index, List<dynamic> destinations) =>
      index == destinations.length - 1 &&
      destinations[index].label == _exitAdminNavLabel;

  Future<void> _openQrTerminal() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const SellerTerminalScreen(),
      ),
    );
  }

  NavigationRailDestination _buildNavDestination({
    required ({IconData icon, IconData selectedIcon, String label}) dest,
    required int index,
    required int transfersTabIndex,
    required int revisionTabIndex,
    required bool revisionActive,
    required int inTransitCount,
    required bool railExtended,
  }) {
    final isTransfers = index == transfersTabIndex;
    final isRevision = index == revisionTabIndex;
    final badgeCount = isTransfers ? inTransitCount : 0;

    Widget icon = Icon(dest.icon);
    Widget selectedIcon = Icon(dest.selectedIcon);
    if (badgeCount > 0) {
      icon = AdminNavIconWithBadge(icon: icon, count: badgeCount);
      selectedIcon =
          AdminNavIconWithBadge(icon: selectedIcon, count: badgeCount);
    } else if (isRevision && revisionActive) {
      icon = Badge(
        backgroundColor: const Color(0xFF1B5E20),
        smallSize: 10,
        child: icon,
      );
      selectedIcon = Badge(
        backgroundColor: const Color(0xFF1B5E20),
        smallSize: 10,
        child: selectedIcon,
      );
    }

    final label = isTransfers && railExtended
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(dest.label)),
              if (badgeCount > 0) ...[
                const SizedBox(width: 8),
                AdminNavCountBadge(count: badgeCount),
              ],
            ],
          )
        : isRevision && railExtended && revisionActive
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: Text(dest.label)),
                  const SizedBox(width: 6),
                  Text(
                    'Идёт',
                    style: AppTypography.caption(
                      fontWeight: FontWeight.w800,
                      color: const Color(0xFF1B5E20),
                    ),
                  ),
                ],
              )
            : Text(dest.label);

    return NavigationRailDestination(
      icon: icon,
      selectedIcon: selectedIcon,
      label: label,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_sessionReady) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final profile = ProfileScope.of(context);
    final isSuperAdmin = AdminAccess.isSuperAdmin(
      supabaseUser: Supabase.instance.client.auth.currentUser,
      localPanelAdmin: profile.isLocalAdminAuthenticated,
    );
    final sellerMode = _isSellerStaffMode(isSuperAdmin);
    final session = _staffSession;

    if (!isSuperAdmin && session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Нет доступа')),
        body: Center(
          child: Text(
            'Смена не открыта. Войдите через профиль (5 тапов).',
            style: AppTypography.productMeta(),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    final destinations =
        sellerMode ? _sellerDestinations() : _adminDestinations(isSuperAdmin);
    final pageCount = sellerMode
        ? destinations.length
        : destinations.length - 1; // последний пункт — выход
    final safeIndex = _selectedIndex.clamp(0, pageCount - 1);
    if (safeIndex != _selectedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedIndex = safeIndex);
      });
    }

    final pages =
        sellerMode && session != null
            ? _sellerPages(session)
            : _adminPages(isSuperAdmin, session);

    final transfersTabIndex =
        destinations.indexWhere((d) => d.label == 'Трансферы');
    final revisionTabIndex =
        destinations.indexWhere((d) => d.label == _revisionNavLabel);
    final railExtended = MediaQuery.sizeOf(context).width >= 960;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          _title(
            isSuperAdmin: isSuperAdmin,
            sellerMode: sellerMode,
            index: safeIndex,
            destCount: destinations.length,
          ),
          style: AppTypography.heading(fontSize: 20),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (sellerMode && session != null) ...[
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Text(
                  'Смена: ${session.name}',
                  style: AppTypography.caption(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
              IconButton(
                tooltip: 'QR-терминал',
                onPressed: _openQrTerminal,
                icon: const Icon(Icons.qr_code_scanner_outlined),
              ),
            TextButton(
              onPressed: _endSellerShift,
              child: const Text('Выйти из смены'),
            ),
          ],
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListenableBuilder(
            listenable: Listenable.merge([
              _transfersInTransitCounter,
              _inventoryActiveCounter,
            ]),
            builder: (context, _) {
              final inTransitCount = _transfersInTransitCounter.count;
              final revisionActive = _inventoryActiveCounter.hasActiveSession;
              return NavigationRail(
                selectedIndex: safeIndex,
                extended: railExtended,
                labelType: railExtended
                    ? NavigationRailLabelType.none
                    : NavigationRailLabelType.selected,
                backgroundColor: AppColors.cardBackground,
                selectedIconTheme: const IconThemeData(color: AppColors.accent),
                selectedLabelTextStyle:
                    AppTypography.caption(fontWeight: FontWeight.w700),
                unselectedLabelTextStyle: AppTypography.productMeta(),
                onDestinationSelected: (index) {
                  if (!sellerMode && _isExitAdminRailIndex(index, destinations)) {
                    _exitAdminPanel();
                    return;
                  }
                  setState(() => _selectedIndex = index);
                  if ((!sellerMode && index == _salesHistoryTabIndex) ||
                      (sellerMode && index == _sellerSalesHistoryTabIndex)) {
                    _scheduleSalesHistoryReload();
                  }
                  if (index == transfersTabIndex) {
                    _refreshTransfersBadge();
                  }
                },
                destinations: [
                  for (var i = 0; i < destinations.length; i++)
                    _buildNavDestination(
                      dest: destinations[i],
                      index: i,
                      transfersTabIndex: transfersTabIndex,
                      revisionTabIndex: revisionTabIndex,
                      revisionActive: revisionActive,
                      inTransitCount: inTransitCount,
                      railExtended: railExtended,
                    ),
                ],
              );
            },
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: IndexedStack(
              index: safeIndex,
              children: pages,
            ),
          ),
        ],
      ),
    );
  }
}