import 'package:flutter/material.dart';

import '../../catalog/models/catalog_item.dart';
import '../../catalog/widgets/cover_art.dart';
import '../../likes/widgets/like_button.dart';
import '../../theme/spotify_colors.dart';

/// A single tappable tile: the item's cover with its title and subtitle beneath.
class CatalogCard extends StatelessWidget {
  const CatalogCard({super.key, required this.item, this.onTap});

  final CatalogItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 150,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                SizedBox(
                  width: 150,
                  height: 150,
                  child: CoverArt(url: item.coverUrl, color: item.coverColor),
                ),
                // Heart in the corner; a translucent black disc keeps it legible
                // over any cover colour.
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(color: Colors.black38, shape: BoxShape.circle),
                    child: LikeButton(id: item.id, size: 18),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(
              item.subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(color: SpotifyColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
