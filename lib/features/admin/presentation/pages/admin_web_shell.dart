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
import '../../application/product_transfers_in_transit_counter.dart';
import '../widgets/admin_nav_count_badge.dart';
import 'jewelry_admin_dashboard.dart';

/// Web-админка: супер-админ или режим продавца (смена после пасхалки).
class AdminWebShell extends StatefulWidget {
  const AdminWebShell({super.key});

  @override
  State<AdminWebShell> createState() => _AdminWebShellState();
}

class _AdminWebShellState extends State<AdminWebShell> {
  static const _salesHistoryTabIndex = 2;

  int _selectedIndex = 0;
  final _salesHistoryKey = GlobalKey<SalesHistoryScreenState>();
  late final DatabaseService _database = DatabaseService.create();
  late final ProductTransfersInTransitCounter _transfersInTransitCounter;

  AdminStaffSession? _staffSession;
  bool _sessionReady = false;

  @override
  void initState() {
    super.initState();
    _transfersInTransitCounter = ProductTransfersInTransitCounter(_database);
    _transfersInTransitCounter.start();
    _loadStaffSession();
  }

  @override
  void dispose() {
    _transfersInTransitCounter.dispose();
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
              icon: Icons.local_shipping_outlined,
              selectedIcon: Icons.local_shipping,
              label: 'Трансферы',
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
        3 => 'Трансферы ICN ↔ ANS',
        4 => 'Приёмка черновиков',
        _ => 'Смена продавца',
      };
    }
    return switch (safe) {
      0 => 'Доктор Ювелирка · Рабочий стол',
      1 => 'Трансферы ICN ↔ ANS',
      2 => 'История продаж · KST / KRW',
      3 when isSuperAdmin => 'Управление персоналом',
      4 when isSuperAdmin => 'Приёмка лома',
      _ => 'Доктор Ювелирка',
    };
  }

  void _scheduleSalesHistoryReload() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _salesHistoryKey.currentState?.reload();
    });
  }

  String _panelActorCode(AdminStaffSession? session) =>
      session?.promoCode ?? 'ADMIN';

  List<Widget> _adminPages(bool isSuperAdmin, AdminStaffSession? session) => [
        JewelryAdminDashboard(
          onPosSaleArchived: _scheduleSalesHistoryReload,
          onProductTransfersChanged: _refreshTransfersBadge,
        ),
        ProductTransfersScreen(
          actorCode: _panelActorCode(session),
          onTransfersMutated: _refreshTransfersBadge,
        ),
        SalesHistoryScreen(key: _salesHistoryKey),
        if (isSuperAdmin) StaffManagementScreen(database: _database),
        if (isSuperAdmin)
          ScrapMetalIntakeScreen(
            database: _database,
            actorCode: _panelActorCode(session),
          ),
      ];

  List<Widget> _sellerPages(AdminStaffSession session) => [
        JewelryAdminDashboard(
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
          hideJournalBulkWriteOff: true,
          actorCode: session.promoCode,
        ),
        ProductTransfersScreen(
          actorCode: session.promoCode,
          onTransfersMutated: _refreshTransfersBadge,
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
    required int inTransitCount,
    required bool railExtended,
  }) {
    final isTransfers = index == transfersTabIndex;
    final badgeCount = isTransfers ? inTransitCount : 0;

    Widget icon = Icon(dest.icon);
    Widget selectedIcon = Icon(dest.selectedIcon);
    if (badgeCount > 0) {
      icon = AdminNavIconWithBadge(icon: icon, count: badgeCount);
      selectedIcon =
          AdminNavIconWithBadge(icon: selectedIcon, count: badgeCount);
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
    final safeIndex = _selectedIndex.clamp(0, destinations.length - 1);
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
    final railExtended = MediaQuery.sizeOf(context).width >= 960;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
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
            listenable: _transfersInTransitCounter,
            builder: (context, _) {
              final inTransitCount = _transfersInTransitCounter.count;
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
                  setState(() => _selectedIndex = index);
                  if (!sellerMode && index == _salesHistoryTabIndex) {
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