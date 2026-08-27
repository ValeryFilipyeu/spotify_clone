import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../player/widgets/mini_player.dart';
import '../../player/widgets/playback_failure_listener.dart';
import '../../router/app_routes.dart';
import '../widgets/offline_banner.dart';

/// The persistent chrome around the three tabs. [StatefulNavigationShell] keeps
/// one Navigator per branch in an IndexedStack, so each tab holds its own
/// back-stack and scroll position. The mini-player sits above the tab bar.
class ScaffoldWithNavBar extends StatelessWidget {
  const ScaffoldWithNavBar({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return PlaybackFailureListener(
      child: Scaffold(
        body: navigationShell,
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Above the player, so the strip sits against the content it
            // describes: everything above this line may be out of date.
            const OfflineBanner(),
            // /player is a root route, so this covers the whole shell.
            MiniPlayer(onTap: () => context.push(Routes.player)),
            NavigationBar(
              selectedIndex: navigationShell.currentIndex,
              onDestinationSelected: (index) => navigationShell.goBranch(
                index,
                // Re-tapping the active tab resets it to its root.
                initialLocation: index == navigationShell.currentIndex,
              ),
              destinations: const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(Icons.search_outlined),
                  selectedIcon: Icon(Icons.search),
                  label: 'Search',
                ),
                NavigationDestination(
                  icon: Icon(Icons.library_music_outlined),
                  selectedIcon: Icon(Icons.library_music),
                  label: 'Library',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
