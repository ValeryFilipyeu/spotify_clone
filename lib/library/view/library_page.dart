import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../catalog/repository/catalog_repository.dart';
import '../cubit/library_cubit.dart';
import 'library_view.dart';

/// Provides a [LibraryCubit] scoped to this tab and kicks off the initial
/// load. Mirrors HomePage: the Page owns the Cubit, the View is presentation.
class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => LibraryCubit(catalogRepository: context.read<CatalogRepository>())..loadLibrary(),
      child: const LibraryView(),
    );
  }
}
