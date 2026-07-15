import 'package:equatable/equatable.dart';

/// A single browsable thing in the catalog (a playlist or album). There is no
/// real backend and no bundled cover images, so instead of an image URL this
/// carries a [coverColor] used to render a gradient placeholder tile -- keeps
/// the app fully offline and deterministic (which also matters for tests).
class CatalogItem extends Equatable {
  const CatalogItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.coverColor,
  });

  final String id;
  final String title;

  /// e.g. an artist name for an album, or a short description for a playlist.
  final String subtitle;

  /// ARGB value used to tint the placeholder cover (see home's card widget).
  final int coverColor;

  @override
  List<Object?> get props => [id, title, subtitle, coverColor];
}
