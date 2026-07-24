import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../theme/spotify_colors.dart';
import '../cubit/likes_cubit.dart';

/// A heart toggle for a single catalog item or track [id]. Reads only the one
/// bool it cares about from [LikesCubit] via `select`, so liking one row never
/// rebuilds the others.
class LikeButton extends StatelessWidget {
  const LikeButton({super.key, required this.id, this.size = 22});

  final String id;
  final double size;

  @override
  Widget build(BuildContext context) {
    final liked = context.select<LikesCubit, bool>((cubit) => cubit.state.isLiked(id));

    return IconButton(
      iconSize: size,
      visualDensity: VisualDensity.compact,
      icon: Icon(
        liked ? Icons.favorite : Icons.favorite_border,
        color: liked ? SpotifyColors.green : SpotifyColors.textSecondary,
      ),
      tooltip: liked ? 'Remove from Your Library' : 'Save to Your Library',
      onPressed: () => context.read<LikesCubit>().toggle(id),
    );
  }
}
