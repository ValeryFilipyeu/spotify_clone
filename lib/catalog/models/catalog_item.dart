import 'package:equatable/equatable.dart';

/// A single browsable thing in the catalog (a playlist or album).
class CatalogItem extends Equatable {
  const CatalogItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.coverColor,
    this.coverUrls = const [],
  });

  final String id;
  final String title;

  /// e.g. an artist name for an album, or a short description for a playlist.
  final String subtitle;

  /// ARGB tint for the gradient shown *beneath* the cover -- the placeholder
  /// while the image downloads, and what stays visible if it never arrives. Kept
  /// alongside the image rather than replaced by it, so a cover is never a hole.
  final int coverColor;

  /// Interchangeable sources for one square cover image, best first, or empty
  /// for an item with no artwork (a perfectly ordinary state in a real catalog,
  /// and the only state this app had before). See [CoverArt], which draws either
  /// case and walks this list when a source does not answer.
  ///
  /// A list rather than a url because the catalog this app talks to serves
  /// artwork from a network of independently operated nodes, any of which can be
  /// down while the others hold the same bytes -- see [AudiusArtwork]. Modelled
  /// here rather than left to the repository because "several places to try" is
  /// a fact about the image, not about one vendor's JSON.
  final List<String> coverUrls;

  @override
  List<Object?> get props => [id, title, subtitle, coverColor, coverUrls];
}
