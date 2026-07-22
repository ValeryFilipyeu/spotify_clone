import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../player/widgets/mini_player.dart';
import '../../router/app_routes.dart';

/// The persistent chrome wrapping the three tabs. [StatefulNavigationShell]
/// (built by go_router's StatefulShellRoute) hosts one Navigator per branch in
/// an IndexedStack, so every tab keeps its own back-stack and scroll position
/// across switches. The mini-player sits directly above the tab bar so it
/// persists across tab switches; it renders nothing until a track is loaded.
class ScaffoldWithNavBar extends StatelessWidget {
  const ScaffoldWithNavBar({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Opens the full "Now Playing" screen. /player is a root route, so
          // this pushes onto the root navigator and covers the whole shell.
          MiniPlayer(onTap: () => context.push(Routes.player)),
          NavigationBar(
            selectedIndex: navigationShell.currentIndex,
            onDestinationSelected: (index) => navigationShell.goBranch(
              index,
              // Re-tapping the active tab resets it to its root (Spotify /
              // go_router example behaviour).
              initialLocation: index == navigationShell.currentIndex,
            ),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
              NavigationDestination(icon: Icon(Icons.search_outlined), selectedIcon: Icon(Icons.search), label: 'Search'),
              NavigationDestination(icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music), label: 'Library'),
            ],
          ),
        ],
      ),
    );
  }
}
