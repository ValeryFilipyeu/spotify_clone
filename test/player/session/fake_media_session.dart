import 'dart:async';

import 'package:spotify_clone/player/session/media_session.dart';

/// A test double for the OS media session. Records everything published to the
/// "lock screen" and lets a test push commands back the way a notification tap
/// would, so PlayerBloc can be tested with no platform channels.
class FakeMediaSession implements MediaSession {
  final _commands = StreamController<MediaSessionCommand>.broadcast();

  /// Every snapshot handed to the OS, in order.
  final List<NowPlaying> published = [];
  int clearCount = 0;

  @override
  Stream<MediaSessionCommand> get commands => _commands.stream;

  @override
  Future<void> update(NowPlaying nowPlaying) async => published.add(nowPlaying);

  @override
  Future<void> clear() async => clearCount++;

  /// Simulates the user pressing a lock-screen / notification / headset button.
  void send(MediaSessionCommand command) => _commands.add(command);

  NowPlaying? get last => published.isEmpty ? null : published.last;

  Future<void> dispose() => _commands.close();
}
