import 'package:flutter/material.dart';

/// Runs a pull-to-refresh and mentions it if it did not work.
///
/// The screens' refresh methods report success by returning a bool rather than
/// emitting a failure state, so that a refresh which fails leaves the content
/// that is already on screen alone. The cost of that choice is that a failure
/// would otherwise be completely silent -- the spinner would just retract and
/// nothing would change, which reads as "nothing to update" rather than "that
/// did not work". This is the other half of the bargain.
Future<void> refreshOrComplain(BuildContext context, Future<bool> Function() refresh) async {
  // Looked up before the await, not after. The refresh outlives the frame, and
  // by the time it resolves this context may be defunct -- which is exactly what
  // use_build_context_synchronously warns about. The messenger lives above the
  // route, so holding it across the gap is safe where holding the context is
  // not.
  final messenger = ScaffoldMessenger.of(context);

  if (await refresh()) return;
  if (!messenger.mounted) return;

  messenger.showSnackBar(
    const SnackBar(content: Text('Could not refresh. Check your connection.')),
  );
}
