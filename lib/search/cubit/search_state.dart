import 'package:equatable/equatable.dart';

import '../../catalog/models/catalog_item.dart';

enum SearchStatus { initial, loading, success, failure }

/// [status] tracks the one-time load of the full catalog. Once loaded,
/// filtering is instant and client-side: [query] is what the user typed and
/// [results] is the filtered subset (empty while the query is empty).
class SearchState extends Equatable {
  const SearchState({
    this.status = SearchStatus.initial,
    this.allItems = const [],
    this.query = '',
    this.results = const [],
    this.errorMessage,
  });

  final SearchStatus status;
  final List<CatalogItem> allItems;
  final String query;
  final List<CatalogItem> results;
  final String? errorMessage;

  SearchState copyWith({
    SearchStatus? status,
    List<CatalogItem>? allItems,
    String? query,
    List<CatalogItem>? results,
    String? errorMessage,
  }) {
    return SearchState(
      status: status ?? this.status,
      allItems: allItems ?? this.allItems,
      query: query ?? this.query,
      results: results ?? this.results,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, allItems, query, results, errorMessage];
}
