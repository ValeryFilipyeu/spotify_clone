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

  /// ARGB tint for the gradient *beneath* the cover: the placeholder while it
  /// downloads, and what stays if it never arrives.
  final int coverColor;

  /// Interchangeable sources for one cover, best first, or empty for an item
  /// with no artwork. [CoverArt] draws either case and walks the list.
  ///
  /// A list because Audius serves artwork from independent nodes, any of which
  /// can be down while the rest hold the same bytes. Modelled here rather than in
  /// the repository: "several places to try" is a fact about the image.
  final List<String> coverUrls;

  @override
  List<Object?> get props => [id, title, subtitle, coverColor, coverUrls];
}
