import 'package:equatable/equatable.dart';

import 'catalog_item.dart';

/// A titled, horizontally-scrollable row on the home screen (e.g.
/// "Made for you", "Popular albums"). The home screen is just a vertical
/// list of these.
class CatalogSection extends Equatable {
  const CatalogSection({required this.title, required this.items});

  final String title;
  final List<CatalogItem> items;

  @override
  List<Object?> get props => [title, items];
}
