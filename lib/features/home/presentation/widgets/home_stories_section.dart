import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../domain/models/story_item.dart';

/// Горизонтальный блок «Истории» с круглыми аватарками и золотой рамкой.
class HomeStoriesSection extends StatelessWidget {
  const HomeStoriesSection({
    super.key,
    this.stories = _defaultStories,
  });

  final List<StoryItem> stories;

  static const List<StoryItem> _defaultStories = [
    StoryItem(
      title: 'Скидки\n-70%',
      icon: Icons.local_offer_outlined,
      isHighlighted: true,
    ),
    StoryItem(title: 'Кольца', icon: Icons.diamond_outlined),
    StoryItem(title: 'Новинки', icon: Icons.auto_awesome_outlined),
    StoryItem(title: 'Серьги', icon: Icons.blur_circular_outlined),
    StoryItem(title: 'Цепи', icon: Icons.link_rounded),
    StoryItem(title: 'Подарки', icon: Icons.card_giftcard_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 108,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: stories.length,
        separatorBuilder: (context, _) => const SizedBox(width: 14),
        itemBuilder: (context, index) {
          return _StoryAvatar(story: stories[index]);
        },
      ),
    );
  }
}

class _StoryAvatar extends StatelessWidget {
  const _StoryAvatar({required this.story});

  final StoryItem story;

  static const double _avatarSize = 64;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 72,
      child: Column(
        children: [
          Container(
            width: _avatarSize + 4,
            height: _avatarSize + 4,
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: story.isHighlighted
                    ? [
                        AppColors.bannerGoldStart,
                        AppColors.accent,
                        AppColors.bannerGoldEnd,
                      ]
                    : [
                        AppColors.accent.withValues(alpha: 0.85),
                        AppColors.bannerGoldStart,
                      ],
              ),
            ),
            child: Container(
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.background,
              ),
              padding: const EdgeInsets.all(3),
              child: CircleAvatar(
                backgroundColor: AppColors.cardBackground,
                child: Icon(
                  story.icon,
                  color: story.isHighlighted
                      ? AppColors.accent
                      : AppColors.textPrimary,
                  size: 26,
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            story.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.caption(
              fontWeight:
                  story.isHighlighted ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
