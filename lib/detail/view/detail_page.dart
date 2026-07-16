import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../catalog/repository/catalog_repository.dart';
import '../cubit/detail_cubit.dart';
import 'detail_view.dart';

/// Provides a [DetailCubit] scoped to this route and kicks off the load for
/// [itemId] (the id comes from the /detail/:id path parameter). Mirrors
/// HomePage: the Page owns the Cubit, the View is pure presentation.
class DetailPage extends StatelessWidget {
  const DetailPage({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => DetailCubit(catalogRepository: context.read<CatalogRepository>())..loadDetail(itemId),
      child: const DetailView(),
    );
  }
}
