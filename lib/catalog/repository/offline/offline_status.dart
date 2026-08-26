/// Whether the app is showing saved data because it could not reach the catalog.
///
/// No connectivity plugin: this reports whether *our own requests* are getting
/// through. A phone attached to a captive portal is online by every OS API and
/// cannot load a thing.
///
/// The cost is that it is found out rather than known in advance -- the first
/// request after a drop has to fail. Worth it: this only ever reports something
/// that definitely happened.
abstract class OfflineStatus {
  /// The current value. A widget on [changes] alone shows nothing until the
  /// state next flips.
  bool get isOffline;

  /// Emits on *changes* only: four failing calls are one event. Broadcast, and
  /// with no replay of a state that has since moved on.
  Stream<bool> get changes;
}

/// For a catalog with no network, which genuinely has no offline state. Not a
/// mock -- the honest answer, which is why it is `const`.
class AlwaysOnline implements OfflineStatus {
  const AlwaysOnline();

  @override
  bool get isOffline => false;

  @override
  Stream<bool> get changes => const Stream<bool>.empty();
}
