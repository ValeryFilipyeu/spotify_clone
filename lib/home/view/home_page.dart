import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../catalog/repository/catalog_repository.dart';
import '../../history/cubit/play_history_cubit.dart';
import '../cubit/home_cubit.dart';
import 'home_view.dart';

/// Provides a [HomeCubit] scoped to this route and kicks off the initial
/// load. Mirrors SignUpPage/LogInPage: the Page owns the Cubit, the View is
/// pure presentation.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      // The history read here is the *current* one, which covers the usual case
      // of it already having loaded with the session. HomeView listens for any
      // that arrives later.
      create: (context) =>
          HomeCubit(catalogRepository: context.read<CatalogRepository>())
            ..loadSections(context.read<PlayHistoryCubit>().state.recentIds),
      child: const HomeView(),
    );
  }
}
