import 'package:equatable/equatable.dart';

/// A single browsable thing in the catalog (a playlist or album).
class CatalogItem extends Equatable {
  const CatalogItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.coverColor,
    this.coverUrl,
  });

  final String id;
  final String title;

  /// e.g. an artist name for an album, or a short description for a playlist.
  final String subtitle;

  /// ARGB tint for the gradient shown *beneath* [coverUrl] -- the placeholder
  /// while the image downloads, and what stays visible if it never arrives. Kept
  /// alongside the image rather than replaced by it, so a cover is never a hole.
  final int coverColor;

  /// A remote square cover image, or null for an item with no artwork (a
  /// perfectly ordinary state in a real catalog, and the only state this app had
  /// before). See [CoverArt], which draws either case.
  final String? coverUrl;

  @override
  List<Object?> get props => [id, title, subtitle, coverColor, coverUrl];
}
