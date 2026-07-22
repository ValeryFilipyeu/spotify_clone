import 'package:equatable/equatable.dart';

import '../../catalog/models/catalog_item.dart';

enum LibraryStatus { initial, loading, success, failure }

/// One evolving state class with a status enum -- same shape as HomeState.
class LibraryState extends Equatable {
  const LibraryState({
    this.status = LibraryStatus.initial,
    this.items = const [],
    this.errorMessage,
  });

  final LibraryStatus status;
  final List<CatalogItem> items;
  final String? errorMessage;

  LibraryState copyWith({
    LibraryStatus? status,
    List<CatalogItem>? items,
    String? errorMessage,
  }) {
    return LibraryState(
      status: status ?? this.status,
      items: items ?? this.items,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, items, errorMessage];
}
