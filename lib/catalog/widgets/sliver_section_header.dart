import 'package:flutter/material.dart';

/// A bold section title as a sliver, used to label the groups ("Playlists &
/// albums", "Songs") in the Search and Library result scrolls.
class SliverSectionHeader extends StatelessWidget {
  const SliverSectionHeader(this.title, {super.key});

  final String title;

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        // header lets a screen reader jump group to group instead of walking
        // every result row in between.
        child: Semantics(
          header: true,
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}
