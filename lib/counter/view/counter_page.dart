import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../bloc/counter_bloc.dart';
import 'counter_view.dart';

/// The routed entry point for the counter feature.
///
/// This is the only widget that knows a [CounterBloc] is involved: it
/// creates one, scopes it to this route via [BlocProvider], and hands off to
/// [CounterView] for the actual UI. Navigating away from this page disposes
/// the bloc automatically.
class CounterPage extends StatelessWidget {
  const CounterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => CounterBloc(),
      child: const CounterView(),
    );
  }
}
