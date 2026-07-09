import 'dart:async';

import 'package:flutter/foundation.dart';

/// Bridges a Stream (AuthBloc.stream) into the Listenable go_router's
/// refreshListenable expects, so a redirect re-runs every time auth state
/// changes -- without adding rxdart as a dependency.
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
