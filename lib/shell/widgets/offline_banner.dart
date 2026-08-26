import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../catalog/repository/offline/offline_status.dart';
import '../../theme/spotify_colors.dart';

/// A strip above the mini-player, shown while the catalog is answering from disk.
///
/// The offline fallback is otherwise invisible, which is the one thing wrong with
/// a cache that works: screens render, refresh completes, nothing errors -- and
/// the tracklist may be six days old.
///
/// In the shell because one insertion point covers all four catalog screens and
/// anything pushed inside them. At the bottom because each tab owns its own
/// `AppBar`. It does not animate: a ticker in the shell's chrome all session, and
/// a moving target for the golden tests, for a strip seen twice a day.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final status = context.read<OfflineStatus>();

    return StreamBuilder<bool>(
      // The stream reports only *changes*, so a widget built after the drop
      // would show nothing without the current value to start from.
      initialData: status.isOffline,
      stream: status.changes,
      builder: (context, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();

        return Semantics(
          // Announced on appearance: there is no error and no spinner, so a
          // screen-reader user has even less to go on than a sighted one.
          liveRegion: true,
          child: Container(
            width: double.infinity,
            color: SpotifyColors.surface,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.cloud_off, size: 14, color: SpotifyColors.textSecondary),
                const SizedBox(width: 8),
                // Not Expanded, which would fill the row and pull the icon
                // off-centre.
                Flexible(
                  child: Text(
                    "You're offline. Showing saved music.",
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: SpotifyColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
