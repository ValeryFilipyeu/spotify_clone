import 'package:equatable/equatable.dart';

import '../../catalog/models/catalog_item.dart';
import '../../catalog/models/catalog_section.dart';

enum HomeStatus { initial, loading, success, failure }

/// One evolving state class with a status enum -- the same choice made for
/// AuthState, and for the same reason: loading/success/failure share one
/// shape and differ only by status, so a sealed hierarchy would buy nothing.
class HomeState extends Equatable {
  const HomeState({
    this.status = HomeStatus.initial,
    this.sections = const [],
    this.itemsById = const {},
    this.errorMessage,
  });

  final HomeStatus status;

  /// The catalog's own sections, identical for every account.
  final List<CatalogSection> sections;

  /// Every browsable item, by id. Loaded alongside [sections] so the personal
  /// rows -- which the catalog only knows as lists of ids -- can be resolved
  /// without a second round trip per id.
  final Map<String, CatalogItem> itemsById;

  final String? errorMessage;

  /// Every row Home should draw for a user whose play history is [recentIds]
  /// (most recent first): their own row, then the catalog's.
  ///
  /// The whole of Home's personalisation, as a pure function -- so it can be
  /// tested for ordering and for the empty case without standing up a widget.
  List<CatalogSection> sectionsFor(Iterable<String> recentIds) {
    final recent = resolve(recentIds);
    return [
      // Above the catalog's own rows: it is the one row the user put there
      // themselves. Omitted entirely until they have played something, rather
      // than shown as an empty row.
      if (recent.isNotEmpty) CatalogSection(title: 'Recently played', items: recent),
      ...sections,
    ];
  }

  /// Resolves [ids] to catalog items, in the order given.
  ///
  /// Ids with nothing behind them are dropped rather than rendered as blanks: a
  /// history entry outlives the catalog it points into, so a playlist that has
  /// since been removed simply stops appearing.
  List<CatalogItem> resolve(Iterable<String> ids) =>
      [for (final id in ids) itemsById[id]].nonNulls.toList();

  HomeState copyWith({
    HomeStatus? status,
    List<CatalogSection>? sections,
    Map<String, CatalogItem>? itemsById,
    String? errorMessage,
  }) {
    return HomeState(
      status: status ?? this.status,
      sections: sections ?? this.sections,
      itemsById: itemsById ?? this.itemsById,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, sections, itemsById, errorMessage];
}
