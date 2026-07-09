import 'package:flutter/material.dart';

import '../theme/spotify_colors.dart';

/// A text-based stand-in wordmark -- deliberately not any real Spotify logo
/// image asset.
class SpotifyWordmark extends StatelessWidget {
  const SpotifyWordmark({super.key, this.fontSize = 24});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.graphic_eq, color: SpotifyColors.green, size: fontSize * 1.2),
        SizedBox(width: fontSize * 0.3),
        Text(
          'spotify clone',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontSize: fontSize,
                fontWeight: FontWeight.w800,
                color: SpotifyColors.white,
              ),
        ),
      ],
    );
  }
}
