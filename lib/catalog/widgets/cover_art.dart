import 'package:flutter/material.dart';

import '../../theme/spotify_colors.dart';

/// Square artwork for a catalog item or a track: the real cover image when there
/// is one, over a tinted gradient that stands in for it.
///
/// The gradient is painted *underneath* the image rather than swapped out for
/// it, which is what keeps this widget stateless: there is no
/// loading/loaded/failed machine to run, because the placeholder is simply never
/// removed. A cover still downloading, one that 404s, and an item with no
/// artwork at all are all the same case -- the gradient shows through.
///
/// Sizes itself to its parent (every caller already wraps its cover in a
/// SizedBox or an AspectRatio) and decodes the bitmap at the size it will
/// actually be painted at.
class CoverArt extends StatelessWidget {
  const CoverArt({
    super.key,
    this.url,
    this.color,
    this.borderRadius = 8,
    this.iconSize = 40,
  });

  /// The remote cover, or null for something with no artwork.
  final String? url;

  /// ARGB tint for the placeholder gradient. Null gets a neutral dark one --
  /// what the player screens use, since a track carries no colour of its own.
  final int? color;

  final double borderRadius;

  /// Size of the music-note glyph on the placeholder, scaled to the cover.
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final url = this.url;
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: Stack(
        // Hands our own constraints to both children, so the image and the
        // gradient behind it are always exactly the same square.
        fit: StackFit.passthrough,
        children: [
          _Placeholder(color: color, iconSize: iconSize),
          if (url != null && url.isNotEmpty) _Cover(url: url),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.color, required this.iconSize});

  final int? color;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final tint = color == null ? SpotifyColors.surfaceBright : Color(color!);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tint, Color.lerp(tint, Colors.black, 0.55)!],
        ),
      ),
      child: Center(
        child: Icon(Icons.music_note, color: Colors.white70, size: iconSize),
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    // LayoutBuilder rather than a size parameter: the widget then decodes
    // correctly wherever it is put, including the full player's cover, which has
    // no fixed size at all. Without cacheWidth a 600px cover in a 48px list tile
    // would hold well over a hundred times the pixels it can possibly show.
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final decodeWidth = width.isFinite && width > 0
            ? (width * MediaQuery.devicePixelRatioOf(context)).round()
            : null;

        return Image.network(
          url,
          fit: BoxFit.cover,
          // Height follows from the width, since covers are square.
          cacheWidth: decodeWidth,
          // Squeezing a 600px photo into a 48px tile aliases visibly at the
          // default (low) quality.
          filterQuality: FilterQuality.medium,
          // Every cover has its title and artist rendered right beside it, so
          // announcing the artwork too would only repeat them.
          excludeFromSemantics: true,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            // Already in the image cache (scrolling back to a row, reopening the
            // player): show it at once, or it would flicker through the fade.
            if (wasSynchronouslyLoaded) return child;
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              child: child,
            );
          },
          // Offline, or a dead url: draw nothing and let the placeholder stand.
          // Deliberately silent -- a missing cover is not worth an error icon.
          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
        );
      },
    );
  }
}
