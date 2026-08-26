import 'package:just_audio/just_audio.dart';

import 'audio_cache_stub.dart' if (dart.library.io) 'audio_cache_io.dart' as platform;

/// Keeps the last few tracks played, so hearing one again costs nothing and
/// works with no network.
///
/// Capped by a count of tracks, not bytes, and deliberately tiny: five is ~35 MB
/// at worst, small enough to need no settings screen and no explaining.
///
/// Note which design this is. Spotify has *downloads* -- chosen, listed, managed.
/// This is the other one: opportunistic and invisible. They look alike from
/// outside and are answerable to completely different expectations.
abstract class AudioCache {
  /// What to hand the engine for [url]: the local file if it is there, and
  /// otherwise a source that streams it while writing it down.
  Future<AudioSource> sourceFor(String url);
}

/// Opens the device's audio cache. Null on the web, where just_audio cannot play
/// from a byte stream at all; that build streams as it always has.
Future<AudioCache?> openAudioCache({int keepTracks = 5}) =>
    platform.openAudioCache(keepTracks: keepTracks);
