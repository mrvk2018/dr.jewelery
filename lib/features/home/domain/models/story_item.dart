import 'package:flutter/material.dart';

/// Модель быстрой подборки в блоке «Истории».
class StoryItem {
  const StoryItem({
    required this.filterKey,
    required this.title,
    required this.icon,
    this.isHighlighted = false,
    this.onTap,
  });

  /// Ключ фильтра каталога (скидки, тип изделия, металл и т.д.).
  final String filterKey;
  final String title;
  final IconData icon;
  final bool isHighlighted;
  final VoidCallback? onTap;
}
