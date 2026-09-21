import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/nav_constants.dart';
import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../cart/presentation/pages/cart_screen.dart';
import '../../../catalog/presentation/pages/catalog_screen.dart';
import '../../../favorites/presentation/pages/favorites_screen.dart';
import '../../../home/presentation/pages/home_screen.dart';
import '../../../profile/presentation/pages/profile_screen.dart';

/// Корневой экран с нижней навигацией из 5 вкладок.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  Future<void> _showExitConfirmationDialog(BuildContext context) async {
    final l10n = context.l10n;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            l10n.exitAppDialogTitle,
            style: AppTypography.heading(fontSize: 20),
          ),
          content: Text(
            l10n.exitAppDialogMessage,
            style: AppTypography.productMeta().copyWith(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.exitAppCancel),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                SystemNavigator.pop();
              },
              child: Text(l10n.exitAppConfirm),
            ),
          ],
        );
      },
    );
  }

  void _onRootBackInvoked(bool didPop) {
    if (didPop) return;

    if (_currentIndex != 0) {
      setState(() => _currentIndex = 0);
      return;
    }

    _showExitConfirmationDialog(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tabLabels = [
      l10n.home,
      l10n.catalog,
      l10n.cart,
      l10n.favorites,
      l10n.profile,
    ];
    final screens = <Widget>[
      const HomeScreen(),
      const CatalogScreen(),
      const CartScreen(),
      const FavoritesScreen(),
      const ProfileScreen(),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) => _onRootBackInvoked(didPop),
      child: Scaffold(
        body: IndexedStack(
          index: _currentIndex,
          children: screens,
        ),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            border: Border(
              top: BorderSide(color: Color(0xFF2A2A2A), width: 0.5),
            ),
          ),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) => setState(() => _currentIndex = index),
            items: [
              for (var index = 0; index < NavConstants.tabs.length; index++)
                BottomNavigationBarItem(
                  icon: Icon(NavConstants.tabs[index].icon),
                  activeIcon: Icon(NavConstants.tabs[index].activeIcon),
                  label: tabLabels[index],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
