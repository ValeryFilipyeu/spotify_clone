import 'package:flutter/material.dart';

import '../../likes/widgets/like_button.dart';
import '../../theme/spotify_colors.dart';
import '../models/catalog_item.dart';
import 'cover_art.dart';

/// A horizontal list row for a catalog item: a small cover plus title/subtitle.
/// Used by Search and Library (Home uses the larger [CatalogCard] inside its
/// horizontally-scrolling rows).
class CatalogListTile extends StatelessWidget {
  const CatalogListTile({super.key, required this.item, this.onTap});

  final CatalogItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: SizedBox(
        width: 48,
        height: 48,
        child: CoverArt(
          url: item.coverUrl,
          color: item.coverColor,
          borderRadius: 4,
          iconSize: 22,
        ),
      ),
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text(item.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: SpotifyColors.textSecondary)),
      trailing: LikeButton(id: item.id),
    );
  }
}
