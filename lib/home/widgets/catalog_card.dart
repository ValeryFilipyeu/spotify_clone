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

  /// Smaller than [_heartTarget] on purpose -- see [build].
  static const double _heartScrim = 34;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return SizedBox(
      width: _width,
      child: Stack(
        children: [
          // One button with one name: without the merge the tap target is an
          // *unnamed* button and a screen reader lands on it saying nothing.
          //
          // The heart is a sibling rather than inside: merged in it would lose
          // its own name and action.
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
          // The disc sits *behind* the button rather than wrapping it, so the
          // two size independently: the button needs 48x48 of hit box, while a
          // 48px disc is a grey blot over the artwork.
          //
          // Centred in one box rather than positioned separately, so they stay
          // concentric whatever size the button reports. Pinned to a corner they
          // drifted apart wherever IconButton was not exactly 48x48.
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
