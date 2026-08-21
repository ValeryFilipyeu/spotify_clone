import 'dart:async';

import 'package:spotify_clone/catalog/repository/offline/offline_status.dart';

/// An [OfflineStatus] a test can flip by hand.
///
/// Both halves move together, the way the real one does: the current value and
/// the event are the same fact reported to two kinds of listener, and a fake that
/// updated only the stream would let a widget pass this suite while showing
/// nothing to anyone who arrived late.
class FakeOfflineStatus implements OfflineStatus {
  /// Named `offline:` at the call site -- Dart strips the underscore when it
  /// derives the parameter name from a private field.
  FakeOfflineStatus({this._offline = false});

  final StreamController<bool> _controller = StreamController<bool>.broadcast();
  bool _offline;

  @override
  bool get isOffline => _offline;

  @override
  Stream<bool> get changes => _controller.stream;

  void flip({required bool offline}) {
    _offline = offline;
    _controller.add(offline);
  }

  Future<void> close() => _controller.close();
}
