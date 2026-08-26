import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../theme/spotify_colors.dart';
import '../cubit/likes_cubit.dart';
import '../models/liked_id.dart';

/// A heart toggle for one [likedId]. Reads only the one bool it cares about
/// from [LikesCubit] via `select`, so liking one row never rebuilds the others.
///
/// It takes a [LikedId] and not a bare id because every heart in the app already
/// knows whether it sits beside an album or a song, and that is the only place
/// the answer is certain -- see [LikedId].
class LikeButton extends StatelessWidget {
  const LikeButton({super.key, required this.likedId, this.itemName, this.size = 22});

  final LikedId likedId;

  /// What is being liked, folded into the button's label. Worth threading
  /// through: without it every heart on a screen announces identically, so a
  /// screen-reader user hears "Save to Your Library" five times over with no way
  /// to tell which row they are on.
  final String? itemName;

  final double size;

  @override
  Widget build(BuildContext context) {
    final liked = context.select<LikesCubit, bool>((cubit) => cubit.state.isLiked(likedId));
    final name = itemName;

    return IconButton(
      iconSize: size,
      // No VisualDensity.compact here, deliberately. It used to be, to keep list
      // rows tight, but it shaves IconButton's 48x48 minimum down to 40x40 --
      // under both the Android (48dp) and iOS (44pt) minimum tap target. The
      // glyph size is unchanged; only the hit box grew.
      icon: Icon(
        liked ? Icons.favorite : Icons.favorite_border,
        color: liked ? SpotifyColors.green : SpotifyColors.textSecondary,
      ),
      // Carries the on/off state into semantics (IconButton turns this into
      // Semantics(selected: ...)), so "liked" is not communicated by a colour
      // swap alone. The tooltip doubles as the accessibility label.
      isSelected: liked,
      tooltip: liked
          ? (name == null ? 'Remove from Your Library' : 'Remove $name from Your Library')
          : (name == null ? 'Save to Your Library' : 'Save $name to Your Library'),
      onPressed: () => context.read<LikesCubit>().toggle(likedId),
    );
  }
}
