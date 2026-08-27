import 'package:shared_preferences/shared_preferences.dart';

import '../../storage/key_value_store.dart';
import 'audio_cache.dart';
import 'web/cache_api_blob_store.dart';
import 'web/web_audio_cache.dart';

/// What the web compiler sees. Null only where the Cache API is missing; see
/// [CacheApiBlobStore.open].
Future<AudioCache?> openAudioCache({int keepTracks = 5}) async {
  final blobs = await CacheApiBlobStore.open();
  if (blobs == null) return null;

  return WebAudioCache(
    blobs,
    SharedPreferencesStore(await SharedPreferences.getInstance()),
    keepTracks: keepTracks,
  );
}
