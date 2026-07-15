import 'package:flutter/material.dart';

import '../../catalog/models/catalog_item.dart';
import '../../theme/spotify_colors.dart';

/// A single tappable tile: a gradient "cover" (no real image asset) with the
/// item's title and subtitle beneath it.
class CatalogCard extends StatelessWidget {
  const CatalogCard({super.key, required this.item, this.onTap});

  final CatalogItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cover = Color(item.coverColor);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 150,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [cover, Color.lerp(cover, Colors.black, 0.55)!],
                ),
              ),
              child: const Center(
                child: Icon(Icons.music_note, color: Colors.white70, size: 40),
              ),
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
