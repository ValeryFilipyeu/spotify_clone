import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../catalog/widgets/catalog_list_tile.dart';
import '../../router/app_routes.dart';
import '../../theme/spotify_colors.dart';
import '../../widgets/error_retry.dart';
import '../cubit/library_cubit.dart';
import '../cubit/library_state.dart';

class LibraryView extends StatelessWidget {
  const LibraryView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your Library')),
      body: BlocBuilder<LibraryCubit, LibraryState>(
        builder: (context, state) {
          switch (state.status) {
            case LibraryStatus.initial:
            case LibraryStatus.loading:
              return const Center(child: CircularProgressIndicator(color: SpotifyColors.green));
            case LibraryStatus.failure:
              return ErrorRetry(
                message: state.errorMessage ?? 'Something went wrong.',
                onRetry: () => context.read<LibraryCubit>().loadLibrary(),
              );
            case LibraryStatus.success:
              return ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: state.items.length,
                itemBuilder: (context, index) {
                  final item = state.items[index];
                  return CatalogListTile(
                    item: item,
                    // push under THIS tab so detail stacks inside Library.
                    onTap: () => context.push(Routes.detailUnder(Routes.library, item.id)),
                  );
                },
              );
          }
        },
      ),
    );
  }
}
