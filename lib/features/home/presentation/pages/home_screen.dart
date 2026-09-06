import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../widgets/home_promo_banner.dart';
import '../widgets/home_recommended_grid.dart';
import '../widgets/home_stories_section.dart';

/// Главный экран в стиле Dr. Jewelry: истории, баннер, рекомендации.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const _initialCountdown = Duration(hours: 2, minutes: 14, seconds: 10);

  late Duration _remaining;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _remaining = _initialCountdown;
    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;

      if (_remaining.inSeconds <= 0) {
        _countdownTimer?.cancel();
        return;
      }

      setState(() {
        _remaining = Duration(seconds: _remaining.inSeconds - 1);
      });
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _HomeHeader()),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
            const SliverToBoxAdapter(child: HomeStoriesSection()),
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
            SliverToBoxAdapter(
              child: HomePromoBanner(
                countdownText: buildPromoCountdownLabel(_remaining),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
            const SliverToBoxAdapter(child: HomeRecommendedTitle()),
            const HomeRecommendedGrid(),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }
}

class _HomeHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppConstants.appName.toUpperCase(),
                  style: AppTypography.heading(fontSize: 22).copyWith(
                    letterSpacing: 2,
                  ),
                ),
                Text(
                  AppConstants.appTagline,
                  style: AppTypography.caption(color: AppColors.textSecondary)
                      .copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.search_rounded),
            color: AppColors.textPrimary,
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.notifications_none_rounded),
            color: AppColors.textPrimary,
          ),
        ],
      ),
    );
  }
}
