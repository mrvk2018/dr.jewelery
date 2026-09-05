import 'package:flutter/material.dart';

import '../../../../shared/widgets/placeholder_tab_screen.dart';

class FavoritesScreen extends StatelessWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlaceholderTabScreen(
      title: 'Избранное',
      icon: Icons.favorite_rounded,
    );
  }
}
