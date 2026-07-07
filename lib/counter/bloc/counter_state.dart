import 'package:equatable/equatable.dart';

/// The state managed by [CounterBloc].
///
/// A counter only ever has one "shape" of state (there's no
/// loading/success/failure to model for a synchronous operation), so this is
/// a single class rather than a sealed hierarchy like [CounterEvent].
class CounterState extends Equatable {
  const CounterState({required this.count});

  final int count;

  /// Returns a copy of this state with the given fields replaced.
  ///
  /// This is the Dart idiom closest to the immutable-update spread
  /// (`{...state, count: newCount}`) you'd reach for in JS/Redux.
  CounterState copyWith({int? count}) {
    return CounterState(count: count ?? this.count);
  }

  @override
  List<Object?> get props => [count];
}
