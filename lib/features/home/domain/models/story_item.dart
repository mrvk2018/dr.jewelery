import 'package:flutter/material.dart';

/// Модель быстрой подборки в блоке «Истории».
class StoryItem {
  const StoryItem({
    required this.title,
    required this.icon,
    this.isHighlighted = false,
  });

  final String title;
  final IconData icon;
  final bool isHighlighted;
}
