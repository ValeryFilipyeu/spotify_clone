import 'package:flutter/material.dart';

/// Runs a pull-to-refresh and mentions it if it did not work.
///
/// The refresh methods return a bool rather than emitting a failure, so a bad
/// refresh leaves the content alone -- which would otherwise be silent, reading
/// as "nothing to update". This is the other half of that bargain.
Future<void> refreshOrComplain(BuildContext context, Future<bool> Function() refresh) async {
  // Before the await: the context may be defunct by the time this resolves. The
  // messenger lives above the route, so holding it across the gap is safe.
  final messenger = ScaffoldMessenger.of(context);

  if (await refresh()) return;
  if (!messenger.mounted) return;

  messenger.showSnackBar(
    const SnackBar(content: Text('Could not refresh. Check your connection.')),
  );
}
