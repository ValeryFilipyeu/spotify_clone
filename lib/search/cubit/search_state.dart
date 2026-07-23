import 'package:equatable/equatable.dart';

import '../../catalog/models/search_results.dart';

/// - [initial]: nothing searched yet (blank query) -> the view shows a prompt.
/// - [loading]: a debounced search is in flight.
/// - [success]: [results] holds the latest matches (possibly empty -> "no
///   results").
/// - [failure]: the search call threw.
enum SearchStatus { initial, loading, success, failure }

/// [query] is the raw text currently in the field; [results] is the matches for
/// the most recently completed search (albums/playlists and songs). The two can
/// briefly disagree while a debounced search is pending or in flight -- the
/// cubit reconciles them.
class SearchState extends Equatable {
  const SearchState({
    this.status = SearchStatus.initial,
    this.query = '',
    this.results = const SearchResults(),
    this.errorMessage,
  });

  final SearchStatus status;
  final String query;
  final SearchResults results;
  final String? errorMessage;

  SearchState copyWith({
    SearchStatus? status,
    String? query,
    SearchResults? results,
    String? errorMessage,
  }) {
    return SearchState(
      status: status ?? this.status,
      query: query ?? this.query,
      results: results ?? this.results,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, query, results, errorMessage];
}
