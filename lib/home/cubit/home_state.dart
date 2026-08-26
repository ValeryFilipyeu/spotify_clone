import 'package:equatable/equatable.dart';

import '../../catalog/models/catalog_item.dart';
import '../../catalog/models/catalog_section.dart';

enum HomeStatus { initial, loading, success, failure }

/// One evolving state class with a status enum, as AuthState: the three states
/// share a shape, so a sealed hierarchy would buy nothing.
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

  /// Every browsable item by id, loaded alongside [sections] so the personal
  /// rows resolve without a round trip each.
  final Map<String, CatalogItem> itemsById;

  final String? errorMessage;

  /// Every row Home draws for a history of [recentIds]: their own row, then the
  /// catalog's. The whole of Home's personalisation as a pure function.
  List<CatalogSection> sectionsFor(Iterable<String> recentIds) {
    final recent = resolve(recentIds);
    return [
      // Above the catalog's rows, and omitted entirely until it has content.
      if (recent.isNotEmpty) CatalogSection(title: 'Recently played', items: recent),
      ...sections,
    ];
  }

  /// Resolves [ids] in order, dropping any with nothing behind them: history
  /// outlives the catalog, so a removed playlist just stops appearing.
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
