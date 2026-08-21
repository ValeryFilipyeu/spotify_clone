import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../catalog/repository/offline/offline_status.dart';
import '../../theme/spotify_colors.dart';

/// A strip above the mini-player, shown while the catalog is answering from what
/// was saved on the device.
///
/// It exists because the offline fallback is otherwise *invisible*, which is the
/// one thing wrong with a cache that works. Screens keep rendering, a
/// pull-to-refresh completes, nothing shows an error -- and the tracklist may be
/// six days old. This is the whole difference between an app that degrades and an
/// app that lies.
///
/// ## Why it lives in the shell
///
/// One insertion point covers everything worth covering. All four catalog-backed
/// screens are branches of the tab shell, and an album pushed from one of them is
/// pushed *inside* that branch, so this sits under Home, Search, Library and any
/// album opened from them. The full-screen player is a root route and covers the
/// shell, which is correct: it is showing a track that is already loaded and
/// playing, and reachability has nothing to say about it.
///
/// ## Why at the bottom
///
/// Above the mini-player rather than under the app bar. Each tab owns its own
/// `AppBar`, so a strip at the top would either push four different app bars down
/// or have to be added to each of them. It also happens to be where Spotify puts
/// its own no-connection notice, which is a reasonable second opinion.
///
/// It does not animate in. An implicit animation here would mean a ticker running
/// inside the shell's chrome for the whole session and a moving target for the
/// widget and golden tests, in exchange for a 200ms slide on a strip that appears
/// perhaps twice a day.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final status = context.read<OfflineStatus>();

    return StreamBuilder<bool>(
      // Both halves of [OfflineStatus] are needed, and this is why: the stream
      // only reports *changes*, so a widget built after the network dropped --
      // switching tabs, opening an album -- would show nothing at all without the
      // current value to start from.
      initialData: status.isOffline,
      stream: status.changes,
      builder: (context, snapshot) {
        if (snapshot.data != true) return const SizedBox.shrink();

        return Semantics(
          // Announced when it appears rather than only when something happens to
          // focus it. A screen reader user has even less to go on than a sighted
          // one here: there is no error, no spinner, and no visible sign that the
          // list they are reading is not current.
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
                // Flexible, not Expanded: the text should take what it needs and
                // ellipsize on a narrow phone rather than always filling the row
                // and pulling the icon off-centre.
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
