import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../screens/sales_history_screen.dart';
import 'jewelry_admin_dashboard.dart';

/// Web-админка: боковая навигация между рабочим столом и историей продаж.
class AdminWebShell extends StatefulWidget {
  const AdminWebShell({super.key});

  @override
  State<AdminWebShell> createState() => _AdminWebShellState();
}

class _AdminWebShellState extends State<AdminWebShell> {
  int _selectedIndex = 0;

  static const _destinations = [
    (icon: Icons.dashboard_outlined, label: 'Рабочий стол'),
    (icon: Icons.history_edu_outlined, label: 'История продаж'),
  ];

  @override
  Widget build(BuildContext context) {
    final title = _selectedIndex == 0
        ? 'Доктор Ювелир · Рабочий стол'
        : 'История продаж · KST / KRW';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(title, style: AppTypography.heading(fontSize: 20)),
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            extended: MediaQuery.sizeOf(context).width >= 960,
            labelType: MediaQuery.sizeOf(context).width >= 960
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.selected,
            backgroundColor: AppColors.cardBackground,
            selectedIconTheme: const IconThemeData(color: AppColors.accent),
            selectedLabelTextStyle: AppTypography.caption(fontWeight: FontWeight.w700),
            unselectedLabelTextStyle: AppTypography.productMeta(),
            onDestinationSelected: (index) => setState(() => _selectedIndex = index),
            destinations: [
              for (final dest in _destinations)
                NavigationRailDestination(
                  icon: Icon(dest.icon),
                  label: Text(dest.label),
                ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: [
                JewelryAdminDashboard(),
                const SalesHistoryScreen(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
