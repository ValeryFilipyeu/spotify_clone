import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../catalog/repository/catalog_repository.dart';
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
      create: (context) => HomeCubit(catalogRepository: context.read<CatalogRepository>())..loadSections(),
      child: const HomeView(),
    );
  }
}
