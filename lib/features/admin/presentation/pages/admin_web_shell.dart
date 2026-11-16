import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/admin/admin_access.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/providers/profile_scope.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/services/database_service.dart';
import '../../../../screens/sales_history_screen.dart';
import '../screens/scrap_metal_intake_screen.dart';
import '../screens/staff_management_screen.dart';
import 'jewelry_admin_dashboard.dart';

/// Web-админка: боковая навигация между рабочим столом и историей продаж.
class AdminWebShell extends StatefulWidget {
  const AdminWebShell({super.key});

  @override
  State<AdminWebShell> createState() => _AdminWebShellState();
}

class _AdminWebShellState extends State<AdminWebShell> {
  static const _salesHistoryTabIndex = 1;

  int _selectedIndex = 0;
  final _salesHistoryKey = GlobalKey<SalesHistoryScreenState>();
  late final DatabaseService _database = DatabaseService.create();

  List<({IconData icon, IconData selectedIcon, String label})> _destinations(
    bool isSuperAdmin,
  ) =>
      [
        (
          icon: Icons.dashboard_outlined,
          selectedIcon: Icons.dashboard,
          label: 'Рабочий стол',
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

  String _title(bool isSuperAdmin, int index) {
    final destinations = _destinations(isSuperAdmin);
    final safe = index.clamp(0, destinations.length - 1);
    return switch (safe) {
      0 => 'Доктор Ювелир · Рабочий стол',
      1 => 'История продаж · KST / KRW',
      2 when isSuperAdmin => 'Управление персоналом',
      3 when isSuperAdmin => 'Приёмка лома',
      _ => 'Доктор Ювелир',
    };
  }

  void _scheduleSalesHistoryReload() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _salesHistoryKey.currentState?.reload();
    });
  }

  List<Widget> _pages(bool isSuperAdmin) => [
        JewelryAdminDashboard(onPosSaleArchived: _scheduleSalesHistoryReload),
        SalesHistoryScreen(key: _salesHistoryKey),
        if (isSuperAdmin) StaffManagementScreen(database: _database),
        if (isSuperAdmin)
          ScrapMetalIntakeScreen(database: _database),
      ];

  @override
  Widget build(BuildContext context) {
    final profile = ProfileScope.of(context);
    final isSuperAdmin = AdminAccess.isSuperAdmin(
      supabaseUser: Supabase.instance.client.auth.currentUser,
      localPanelAdmin: profile.isLocalAdminAuthenticated,
    );
    final destinations = _destinations(isSuperAdmin);
    final safeIndex = _selectedIndex.clamp(0, destinations.length - 1);
    if (safeIndex != _selectedIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedIndex = safeIndex);
      });
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          _title(isSuperAdmin, safeIndex),
          style: AppTypography.heading(fontSize: 20),
        ),
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
              if (index == _salesHistoryTabIndex) {
                _scheduleSalesHistoryReload();
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
              children: _pages(isSuperAdmin),
            ),
          ),
        ],
      ),
    );
  }
}
