/// Whether the app is currently showing saved data because it could not reach
/// the catalog.
///
/// Named for what the UI needs to say and not for what the OS knows, because
/// those are different facts and only one of them is worth showing anybody.
/// There is no connectivity plugin behind this and no network interface being
/// polled: it reports whether *our own requests* are getting through, which is
/// the question that matters and the only one that cannot be wrong. A phone can
/// be firmly attached to a wifi network that goes nowhere -- a hotel captive
/// portal, a router with no upstream -- and every connectivity API will
/// cheerfully call that online.
///
/// The cost of deriving it from failures rather than announcements is that it is
/// found out rather than known in advance: the first request after the network
/// drops has to fail before anything turns on. Since the alternative reports a
/// state that is sometimes false, and this one only ever reports a state that
/// definitely happened, that seems like the right way round.
abstract class OfflineStatus {
  /// What the last catalog request found. Read this for the current value; a
  /// widget subscribing to [changes] alone would show nothing until the state
  /// next flipped.
  bool get isOffline;

  /// Emits on every *change* to [isOffline], not once per request -- a screen
  /// making four calls while the network is down is one event, not four.
  ///
  /// Broadcast, because more than one thing may want to watch it and nothing
  /// wants a replay of a state that has since changed.
  Stream<bool> get changes;
}

/// The catalog cannot go offline, so nothing ever needs saying about it.
///
/// What the fake catalog and every widget test get. Not a mock: a repository with
/// no network genuinely has no offline state, and this is the honest [OfflineStatus]
/// for one -- which is why it is `const` and has no plumbing behind it.
class AlwaysOnline implements OfflineStatus {
  const AlwaysOnline();

  @override
  bool get isOffline => false;

  @override
  Stream<bool> get changes => const Stream<bool>.empty();
}
