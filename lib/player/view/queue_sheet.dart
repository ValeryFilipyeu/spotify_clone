import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../catalog/models/track.dart';
import '../../theme/spotify_colors.dart';
import '../../widgets/duration_format.dart';
import '../bloc/player_bloc.dart';
import '../bloc/player_event.dart';
import '../bloc/player_state.dart';

/// The "Up next" queue, shown as a modal bottom sheet from the full player.
/// Mirrors Spotify's queue: the playing track sits in its own non-editable
/// "Now playing" section, and everything after it can be reordered by dragging,
/// removed, or jumped to by tapping.
class QueueSheet extends StatelessWidget {
  const QueueSheet({super.key});

  /// PlayerBloc is provided above MaterialApp, so the modal route (pushed on the
  /// Navigator *inside* it) can still read it.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: SpotifyColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const QueueSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ConstrainedBox(
        // Cap the sheet so a long queue scrolls instead of covering the screen;
        // a short one still shrink-wraps (see Flexible + shrinkWrap below).
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.75),
        child: BlocBuilder<PlayerBloc, PlayerState>(
          builder: (context, state) {
            final current = state.currentTrack;
            if (current == null) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: Text('Nothing playing')),
              );
            }

            final upNext = state.upNext;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _SheetHeader(),
                const _SectionLabel('Now playing'),
                _QueueRow(track: current, isCurrent: true),
                const _SectionLabel('Next up'),
                if (upNext.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 24),
                    child: Text(
                      'Nothing queued after this track.',
                      style: TextStyle(color: SpotifyColors.textSecondary),
                    ),
                  )
                else
                  Flexible(
                    child: ReorderableListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 16),
                      // Explicit handles (below) instead of the platform
                      // defaults, which only appear on desktop -- this way drag
                      // works the same on mobile, web and macOS.
                      buildDefaultDragHandles: false,
                      itemCount: upNext.length,
                      // onReorderItem (not the deprecated onReorder) already
                      // accounts for the dragged row being lifted out, so
                      // newIndex is the final slot -- no off-by-one to undo.
                      onReorderItem: (oldIndex, newIndex) {
                        // These indices are into the "Next up" sublist; shift
                        // them into full-queue space for the bloc.
                        final offset = state.currentIndex + 1;
                        context.read<PlayerBloc>().add(PlayerQueueReordered(
                              oldIndex: offset + oldIndex,
                              newIndex: offset + newIndex,
                            ));
                      },
                      itemBuilder: (context, index) {
                        final absolute = state.currentIndex + 1 + index;
                        final track = upNext[index];
                        return _QueueRow(
                          // Index-qualified: the same track can legitimately
                          // appear twice via "Add to queue", and duplicate keys
                          // would break the reorderable list.
                          key: ValueKey('$absolute-${track.id}'),
                          track: track,
                          dragIndex: index,
                          onTap: () => context.read<PlayerBloc>().add(PlayerQueueIndexSelected(absolute)),
                          onRemove: () => context.read<PlayerBloc>().add(PlayerQueueItemRemoved(absolute)),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SheetHeader extends StatelessWidget {
  const _SheetHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Queue',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: SpotifyColors.textSecondary),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: SpotifyColors.textSecondary,
                letterSpacing: 1,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}

/// One row of the queue. The current track renders without a drag handle or
/// remove button (it is the "Now playing" entry).
class _QueueRow extends StatelessWidget {
  const _QueueRow({
    super.key,
    required this.track,
    this.isCurrent = false,
    this.dragIndex,
    this.onTap,
    this.onRemove,
  });

  final Track track;
  final bool isCurrent;
  final int? dragIndex;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return ListTile(
      onTap: onTap,
      leading: SizedBox(
        width: 40,
        height: 40,
        child: DecoratedBox(
          decoration: const BoxDecoration(color: SpotifyColors.surfaceBright),
          child: Icon(
            isCurrent ? Icons.volume_up : Icons.music_note,
            color: isCurrent ? SpotifyColors.green : Colors.white70,
            size: 20,
          ),
        ),
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: isCurrent ? const TextStyle(color: SpotifyColors.green) : null,
      ),
      subtitle: Text(
        track.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textTheme.bodySmall?.copyWith(color: SpotifyColors.textSecondary),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onRemove == null)
            Text(
              formatDuration(track.duration),
              style: textTheme.bodySmall?.copyWith(color: SpotifyColors.textSecondary),
            )
          else
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: SpotifyColors.textSecondary),
              iconSize: 20,
              visualDensity: VisualDensity.compact,
              tooltip: 'Remove from queue',
              onPressed: onRemove,
            ),
          if (dragIndex != null)
            ReorderableDragStartListener(
              index: dragIndex!,
              child: const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Icon(Icons.drag_handle, color: SpotifyColors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }
}
