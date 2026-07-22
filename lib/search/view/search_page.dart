import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../catalog/repository/catalog_repository.dart';
import '../cubit/search_cubit.dart';
import 'search_view.dart';

/// Provides a [SearchCubit] scoped to this tab and loads the catalog it filters
/// over. Mirrors HomePage: the Page owns the Cubit, the View is presentation.
class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => SearchCubit(catalogRepository: context.read<CatalogRepository>())..loadCatalog(),
      child: const SearchView(),
    );
  }
}
