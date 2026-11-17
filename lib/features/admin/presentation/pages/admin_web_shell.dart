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
import '../../../seller/presentation/screens/seller_terminal_screen.dart';
import 'jewelry_admin_dashboard.dart';

/// Web-админка: супер-админ или режим продавца (смена после пасхалки).
class AdminWebShell extends StatefulWidget {
  const AdminWebShell({super.key});

  @override
  State<AdminWebShell> createState() => _AdminWebShellState();
}

class _AdminWebShellState extends State<AdminWebShell> {
  static const _salesHistoryTabIndex = 2;
  static const _transfersTabIndexAdmin = 1;

  int _selectedIndex = 0;
  final _salesHistoryKey = GlobalKey<SalesHistoryScreenState>();
  late final DatabaseService _database = DatabaseService.create();

  AdminStaffSession? _staffSession;
  bool _sessionReady = false;

  @override
  void initState() {
    super.initState();
    _loadStaffSession();
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
        1 => 'Приёмка и журнал лома',
        2 => 'Трансферы ICN ↔ ANS',
        3 => 'Приёмка черновиков',
        _ => 'Смена продавца',
      };
    }
    return switch (safe) {
      0 => 'Доктор Ювелир · Рабочий стол',
      1 => 'Трансферы ICN ↔ ANS',
      2 => 'История продаж · KST / KRW',
      3 when isSuperAdmin => 'Управление персоналом',
      4 when isSuperAdmin => 'Приёмка лома',
      _ => 'Доктор Ювелир',
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
        JewelryAdminDashboard(onPosSaleArchived: _scheduleSalesHistoryReload),
        ProductTransfersScreen(actorCode: _panelActorCode(session)),
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
        ),
        ScrapMetalIntakeScreen(
          database: _database,
          initialSellerCode: session.promoCode,
          initialSellerName: session.name,
          hideJournalBulkWriteOff: true,
          actorCode: session.promoCode,
        ),
        ProductTransfersScreen(actorCode: session.promoCode),
        DraftIntakeScreen(
          database: _database,
          sellerStaffMode: true,
          actorCode: session.promoCode,
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
          NavigationRail(
            selectedIndex: safeIndex,
            extended: MediaQuery.sizeOf(context).width >= 960,
            labelType: MediaQuery.sizeOf(context).width >= 960
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
              if (!sellerMode && index == _transfersTabIndexAdmin) {
                setState(() {});
              }
            },
            destinations: [
              for (final dest in destinations)
                NavigationRailDestination(
                  icon: Icon(dest.icon),
                  selectedIcon: Icon(dest.selectedIcon),
                  label: Text(dest.label),
                ),
            ],
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