import 'package:equatable/equatable.dart';

import '../../catalog/models/catalog_detail.dart';

enum DetailStatus { initial, loading, success, failure }

/// One evolving state class with a status enum -- same choice as HomeState and
/// AuthState. [detail] is null until a successful load.
class DetailState extends Equatable {
  const DetailState({
    this.status = DetailStatus.initial,
    this.detail,
    this.errorMessage,
  });

  final DetailStatus status;
  final CatalogDetail? detail;
  final String? errorMessage;

  DetailState copyWith({
    DetailStatus? status,
    CatalogDetail? detail,
    String? errorMessage,
  }) {
    return DetailState(
      status: status ?? this.status,
      detail: detail ?? this.detail,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, detail, errorMessage];
}
