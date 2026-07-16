import 'package:equatable/equatable.dart';

import 'catalog_item.dart';
import 'track.dart';

/// A single album/playlist opened from the home screen: the [item] used as
/// the header, plus its [tracks].
class CatalogDetail extends Equatable {
  const CatalogDetail({required this.item, required this.tracks});

  final CatalogItem item;
  final List<Track> tracks;

  /// Sum of every track's duration -- shown in the header ("42 min").
  Duration get totalDuration => tracks.fold(Duration.zero, (sum, track) => sum + track.duration);

  @override
  List<Object?> get props => [item, tracks];
}
