import 'package:just_audio/just_audio.dart';

import 'audio_cache_stub.dart' if (dart.library.io) 'audio_cache_io.dart' as platform;

/// Keeps the last few tracks played on the device, so hearing one again costs
/// nothing and works with no network.
///
/// Small on purpose. A track is three to seven megabytes -- two orders of
/// magnitude more than anything else this app saves -- so this is capped by a
/// count of tracks rather than by a byte budget, and the count is deliberately
/// tiny. Five of them is around 35 MB at worst, which is small enough that the
/// cache needs no settings screen, no progress indicator and no explaining: it is
/// under the threshold where a user would ever go looking for it.
///
/// That is a different decision from the one a real music app makes. Spotify has
/// *downloads*: the user chooses, sees a list, and manages the space. This is the
/// other design -- opportunistic, invisible, and bounded so tightly that it never
/// has to be managed. Worth knowing which one this is, because the two look
/// similar from the outside and are answerable to completely different
/// expectations.
abstract class AudioCache {
  /// What to hand the engine for [url]: the local file if it is there, and
  /// otherwise a source that streams it while writing it down.
  Future<AudioSource> sourceFor(String url);
}

/// Opens the device's audio cache, or null where there is nowhere to put one.
///
/// Null on the web, where just_audio cannot play from a byte stream at all --
/// `StreamAudioSource` and everything built on it is unsupported there. The web
/// build streams as it always has.
Future<AudioCache?> openAudioCache({int keepTracks = 5}) =>
    platform.openAudioCache(keepTracks: keepTracks);
