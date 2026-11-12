import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/admin/admin_access.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../shared/providers/profile_scope.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../screens/sales_history_screen.dart';
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

  List<({IconData icon, String label})> _destinations(bool isSuperAdmin) => [
        (icon: Icons.dashboard_outlined, label: 'Рабочий стол'),
        (icon: Icons.history_edu_outlined, label: 'История продаж'),
        if (isSuperAdmin)
          (
            icon: Icons.badge_outlined,
            label: 'Управление персоналом',
          ),
      ];

  String _title(bool isSuperAdmin) {
    if (_selectedIndex == 0) return 'Доктор Ювелир · Рабочий стол';
    if (_selectedIndex == 1) return 'История продаж · KST / KRW';
    if (isSuperAdmin && _selectedIndex == 2) {
      return 'Управление персоналом';
    }
    return 'Доктор Ювелир';
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
        if (isSuperAdmin) StaffManagementScreen(),
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
        title: Text(_title(isSuperAdmin), style: AppTypography.heading(fontSize: 20)),
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
