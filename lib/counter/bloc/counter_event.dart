import 'package:equatable/equatable.dart';

/// Events that can be dispatched to a [CounterBloc].
///
/// Marking this `sealed` means the compiler knows [CounterIncremented] and
/// [CounterDecremented] are the *only* possible subtypes, so a `switch` over
/// a [CounterEvent] can be exhaustive with no `default` case -- the same
/// guarantee a TypeScript discriminated union gives you.
sealed class CounterEvent extends Equatable {
  const CounterEvent();

  @override
  List<Object?> get props => [];
}

/// Requests that the count be increased by one.
class CounterIncremented extends CounterEvent {
  const CounterIncremented();
}

/// Requests that the count be decreased by one.
class CounterDecremented extends CounterEvent {
  const CounterDecremented();
}
