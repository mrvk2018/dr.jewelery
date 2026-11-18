import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';

/// Красный счётчик (как POS-корзина: `AppColors.saleRed` / Material `Badge`).
class AdminNavCountBadge extends StatelessWidget {
  const AdminNavCountBadge({
    super.key,
    required this.count,
    this.compact = false,
  });

  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();

    final label = count > 99 ? '99+' : '$count';
    final textStyle = TextStyle(
      color: Colors.white,
      fontSize: compact ? 10 : 11,
      fontWeight: FontWeight.w700,
      height: 1,
    );

    if (compact) {
      return Container(
        constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: const BoxDecoration(
          color: AppColors.saleRed,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(label, style: textStyle),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.saleRed,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label, style: textStyle),
    );
  }
}

/// Оборачивает иконку пункта меню (видно при свёрнутом `NavigationRail`).
class AdminNavIconWithBadge extends StatelessWidget {
  const AdminNavIconWithBadge({
    super.key,
    required this.icon,
    required this.count,
  });

  final Widget icon;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Badge(
      isLabelVisible: count > 0,
      backgroundColor: AppColors.saleRed,
      textColor: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      label: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
      ),
      child: icon,
    );
  }
}