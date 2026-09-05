import 'package:flutter/material.dart';

/// Константы нижней навигации приложения.
abstract final class NavConstants {
  static const List<NavTabItem> tabs = [
    NavTabItem(
      label: 'Главная',
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
    ),
    NavTabItem(
      label: 'Каталог',
      icon: Icons.grid_view_outlined,
      activeIcon: Icons.grid_view_rounded,
    ),
    NavTabItem(
      label: 'Корзина',
      icon: Icons.shopping_bag_outlined,
      activeIcon: Icons.shopping_bag_rounded,
    ),
    NavTabItem(
      label: 'Избранное',
      icon: Icons.favorite_border_rounded,
      activeIcon: Icons.favorite_rounded,
    ),
    NavTabItem(
      label: 'Профиль',
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
    ),
  ];
}

class NavTabItem {
  const NavTabItem({
    required this.label,
    required this.icon,
    required this.activeIcon,
  });

  final String label;
  final IconData icon;
  final IconData activeIcon;
}
