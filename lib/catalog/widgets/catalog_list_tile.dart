import 'package:flutter/material.dart';

import '../../likes/widgets/like_button.dart';
import '../../theme/spotify_colors.dart';
import '../models/catalog_item.dart';

/// A horizontal list row for a catalog item: a small gradient "cover" plus
/// title/subtitle. Used by Search and Library (Home uses the larger
/// [CatalogCard] inside its horizontally-scrolling rows).
class CatalogListTile extends StatelessWidget {
  const CatalogListTile({super.key, required this.item, this.onTap});

  final CatalogItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cover = Color(item.coverColor);

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [cover, Color.lerp(cover, Colors.black, 0.55)!],
          ),
        ),
        child: const Icon(Icons.music_note, color: Colors.white70, size: 22),
      ),
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text(item.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: SpotifyColors.textSecondary)),
      trailing: LikeButton(id: item.id),
    );
  }
}
