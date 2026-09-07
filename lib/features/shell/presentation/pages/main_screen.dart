import 'package:flutter/material.dart';

import '../../../../core/constants/nav_constants.dart';
import '../../../../core/extensions/context_extensions.dart';
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

    return Scaffold(
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
    );
  }
}
