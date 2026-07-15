import 'package:equatable/equatable.dart';

import '../../catalog/models/catalog_section.dart';

enum HomeStatus { initial, loading, success, failure }

/// One evolving state class with a status enum -- the same choice made for
/// AuthState, and for the same reason: loading/success/failure share one
/// shape and differ only by status, so a sealed hierarchy would buy nothing.
class HomeState extends Equatable {
  const HomeState({
    this.status = HomeStatus.initial,
    this.sections = const [],
    this.errorMessage,
  });

  final HomeStatus status;
  final List<CatalogSection> sections;
  final String? errorMessage;

  HomeState copyWith({
    HomeStatus? status,
    List<CatalogSection>? sections,
    String? errorMessage,
  }) {
    return HomeState(
      status: status ?? this.status,
      sections: sections ?? this.sections,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, sections, errorMessage];
}
