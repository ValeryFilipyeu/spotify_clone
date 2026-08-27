@TestOn('vm')
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/router/go_router_refresh_stream.dart';

void main() {
  test('notifies on every event, which is what re-runs redirect', () async {
    final source = StreamController<int>.broadcast();
    final refresh = GoRouterRefreshStream(source.stream);
    var notifications = 0;
    refresh.addListener(() => notifications++);

    source
      ..add(1)
      ..add(2)
      ..add(3);
    await pumpEventQueue();

    expect(notifications, 3);
    await source.close();
  });

  test('drives off a single-subscription stream too', () async {
    // Why the implementation calls asBroadcastStream: a source that allows only
    // one listener would otherwise throw the moment go_router attached.
    final source = StreamController<int>();
    final refresh = GoRouterRefreshStream(source.stream);
    var notified = false;
    refresh.addListener(() => notified = true);

    source.add(1);
    await pumpEventQueue();

    expect(notified, isTrue);
    await source.close();
  });

  test('stops listening once disposed', () async {
    final source = StreamController<int>.broadcast();
    final refresh = GoRouterRefreshStream(source.stream);
    var notifications = 0;
    refresh.addListener(() => notifications++);

    refresh.dispose();
    source.add(1);
    await pumpEventQueue();

    // Not just "no notification": a live subscription would call
    // notifyListeners on a disposed ChangeNotifier, which throws.
    expect(notifications, 0);
    await source.close();
  });
}
