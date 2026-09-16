import 'package:flutter/material.dart';

import '../../../../core/extensions/context_extensions.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../shared/providers/catalog_scope.dart';
import '../../domain/models/story_item.dart';

/// Горизонтальный блок «Истории» с круглыми аватарками и золотой рамкой.
class HomeStoriesSection extends StatelessWidget {
  const HomeStoriesSection({super.key});

  static List<StoryItem> storiesFor(
    BuildContext context,
    String? activeFilterKey,
    void Function(String filterKey) onFilterTap,
  ) {
    final l10n = context.l10n;

    StoryItem story({
      required String filterKey,
      required String title,
      required IconData icon,
    }) {
      final isActive = filterKey == 'all'
          ? activeFilterKey == null
          : activeFilterKey == filterKey;

      return StoryItem(
        filterKey: filterKey,
        title: title,
        icon: icon,
        isHighlighted: isActive,
        onTap: () => onFilterTap(filterKey),
      );
    }

    return [
      story(
        filterKey: 'all',
        title: 'Все',
        icon: Icons.grid_view_rounded,
      ),
      story(
        filterKey: 'discounts',
        title: l10n.homeStoryDiscounts,
        icon: Icons.local_offer_outlined,
      ),
      story(
        filterKey: 'rings',
        title: l10n.homeStoryRings,
        icon: Icons.diamond_outlined,
      ),
      story(
        filterKey: 'new',
        title: l10n.homeStoryNew,
        icon: Icons.auto_awesome_outlined,
      ),
      story(
        filterKey: 'earrings',
        title: l10n.homeStoryEarrings,
        icon: Icons.blur_circular_outlined,
      ),
      story(
        filterKey: 'chains',
        title: l10n.homeStoryChains,
        icon: Icons.link_rounded,
      ),
      story(
        filterKey: 'gifts',
        title: l10n.homeStoryGifts,
        icon: Icons.card_giftcard_outlined,
      ),
      story(
        filterKey: 'gold',
        title: 'Золото',
        icon: Icons.brightness_high_outlined,
      ),
      story(
        filterKey: 'silver',
        title: 'Серебро',
        icon: Icons.tonality_outlined,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final catalog = CatalogScope.of(context);
    final stories = storiesFor(
      context,
      catalog.homeStoryFilterKey,
      catalog.toggleHomeStoryFilter,
    );

    return SizedBox(
      height: 118,
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
      child: InkWell(
        onTap: () => story.onTap?.call(),
        borderRadius: BorderRadius.circular(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                story.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.caption(
                  fontWeight:
                      story.isHighlighted ? FontWeight.w600 : FontWeight.w500,
                ).copyWith(height: 1.15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
