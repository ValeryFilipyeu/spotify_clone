import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/counter/counter.dart';

void main() {
  group('CounterBloc', () {
    test('initial state is CounterState(count: 0)', () {
      expect(CounterBloc().state, const CounterState(count: 0));
    });

    blocTest<CounterBloc, CounterState>(
      'emits count 1 when CounterIncremented is added',
      build: CounterBloc.new,
      act: (bloc) => bloc.add(const CounterIncremented()),
      expect: () => [const CounterState(count: 1)],
    );

    blocTest<CounterBloc, CounterState>(
      'emits count -1 when CounterDecremented is added',
      build: CounterBloc.new,
      act: (bloc) => bloc.add(const CounterDecremented()),
      expect: () => [const CounterState(count: -1)],
    );

    blocTest<CounterBloc, CounterState>(
      'emits [1, 0] when incremented then decremented',
      build: CounterBloc.new,
      act: (bloc) => bloc
        ..add(const CounterIncremented())
        ..add(const CounterDecremented()),
      expect: () => [
        const CounterState(count: 1),
        const CounterState(count: 0),
      ],
    );
  });
}
