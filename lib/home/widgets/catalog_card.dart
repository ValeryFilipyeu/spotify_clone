import 'package:flutter/material.dart';

import '../../catalog/models/catalog_item.dart';
import '../../catalog/widgets/cover_art.dart';
import '../../likes/models/liked_id.dart';
import '../../likes/widgets/like_button.dart';
import '../../theme/spotify_colors.dart';

/// A single tappable tile: the item's cover with its title and subtitle beneath.
class CatalogCard extends StatelessWidget {
  const CatalogCard({super.key, required this.item, this.onTap});

  final CatalogItem item;
  final VoidCallback? onTap;

  static const double _width = 150;

  /// Minimum legal tap target: 48dp on Android, 44pt on iOS.
  static const double _heartTarget = 48;

  /// The visible disc behind the heart, kept smaller than [_heartTarget] on
  /// purpose -- see the note in [build].
  static const double _heartScrim = 34;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SizedBox(
      width: _width,
      child: Stack(
        children: [
          // The card is one button with one name. MergeSemantics folds the cover,
          // title and subtitle into the InkWell's own node -- without it the tap
          // target is an *unnamed* button with the title sitting beside it as a
          // separate node, so a screen reader lands on the card and says nothing
          // at all. (labeledTapTargetGuideline catches exactly this.)
          //
          // The heart is deliberately a sibling of this subtree rather than
          // inside it: merged in, it would lose its own name and its own tap
          // action, and the card would offer no way to like anything.
          MergeSemantics(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: _width,
                    height: _width,
                    child: CoverArt(urls: item.coverUrls, color: item.coverColor),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    item.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(color: SpotifyColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          // A translucent disc so the heart stays legible on any cover. It sits
          // *behind* the button rather than wrapping it, so the two can be sized
          // independently: the button needs a full 48x48 hit box, while a 48px
          // disc would be a heavy grey blot over the artwork.
          //
          // Both are centred in one box instead of being positioned separately,
          // so they stay concentric whatever size the button reports. They used
          // to be two Positioneds pinned to the same corner, which silently drew
          // the heart 4px up and 4px right of its disc anywhere IconButton was
          // not exactly 48x48 -- as it is not under a desktop visual density.
          Positioned(
            right: 0,
            top: _width - _heartTarget,
            child: SizedBox.square(
              dimension: _heartTarget,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  IgnorePointer(
                    child: Container(
                      width: _heartScrim,
                      height: _heartScrim,
                      decoration: const BoxDecoration(
                        color: Colors.black54,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  LikeButton(likedId: LikedId.item(item.id), itemName: item.title, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
