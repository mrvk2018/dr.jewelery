import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

/// Премиальный промо-баннер с акцией и живым таймером обратного отсчёта.
class HomePromoBanner extends StatelessWidget {
  const HomePromoBanner({
    super.key,
    required this.countdownText,
    this.title = 'ГРАНДИОЗНАЯ\nРАСПРОДАЖА',
    this.subtitle = 'Эксклюзивные украшения по особым ценам',
  });

  final String title;
  final String subtitle;
  final String countdownText;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.bannerDark,
              AppColors.primary,
              AppColors.bannerGoldStart,
            ],
            stops: [0.0, 0.55, 1.0],
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.18),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              right: -20,
              top: -20,
              child: Icon(
                Icons.diamond_outlined,
                size: 120,
                color: AppColors.accent.withValues(alpha: 0.12),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: AppColors.accent.withValues(alpha: 0.5),
                      ),
                    ),
                    child: Text(
                      'LIMITED OFFER',
                      style: AppTypography.caption(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w700,
                      ).copyWith(letterSpacing: 1.5, fontSize: 10),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: AppTypography.bannerTitle(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: AppTypography.caption(
                      color: AppColors.textOnPrimary.withValues(alpha: 0.75),
                    ).copyWith(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  _CountdownChip(text: countdownText),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountdownChip extends StatelessWidget {
  const _CountdownChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.textOnPrimary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.accent.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.timer_outlined,
            color: AppColors.accent,
            size: 18,
          ),
          const SizedBox(width: 8),
          Text(text, style: AppTypography.countdown()),
        ],
      ),
    );
  }
}

/// Форматирует длительность в строку HH:MM:SS.
String formatCountdown(Duration duration) {
  final totalSeconds = duration.inSeconds.clamp(0, 86400);
  final hours = (totalSeconds ~/ 3600).toString().padLeft(2, '0');
  final minutes = ((totalSeconds % 3600) ~/ 60).toString().padLeft(2, '0');
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}

/// Текст таймера для промо-баннера.
String buildPromoCountdownLabel(Duration remaining) {
  return 'До конца осталось ${formatCountdown(remaining)}';
}
