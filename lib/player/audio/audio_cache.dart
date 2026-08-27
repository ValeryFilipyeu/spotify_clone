import 'package:just_audio/just_audio.dart';

import 'audio_cache_stub.dart'
    if (dart.library.io) 'audio_cache_io.dart'
    if (dart.library.js_interop) 'audio_cache_web.dart'
    as platform;

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
  /// What to hand the engine for [url]: the saved copy if there is one, and
  /// otherwise a source that streams while the copy is made.
  Future<AudioSource> sourceFor(String url);
}

/// Opens the platform's audio cache, or null where there is nowhere to put one.
///
/// Both real implementations honour [keepTracks] and play with no network; they
/// differ in that mobile writes while it streams and the web cannot. See
/// [WebAudioCache].
Future<AudioCache?> openAudioCache({int keepTracks = 5}) =>
    platform.openAudioCache(keepTracks: keepTracks);
