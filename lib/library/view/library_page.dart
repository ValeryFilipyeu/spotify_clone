import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../catalog/repository/catalog_repository.dart';
import '../../likes/cubit/likes_cubit.dart';
import '../cubit/library_cubit.dart';
import 'library_view.dart';

/// Provides a [LibraryCubit] scoped to this tab and kicks off the initial
/// load. Mirrors HomePage: the Page owns the Cubit, the View is presentation.
class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      // Whatever is liked right now; LibraryView keeps it in step as that
      // changes, including the first restore if it has not finished yet.
      create: (context) =>
          LibraryCubit(catalogRepository: context.read<CatalogRepository>())
            ..loadLibrary(context.read<LikesCubit>().state.likedIds),
      child: const LibraryView(),
    );
  }
}
