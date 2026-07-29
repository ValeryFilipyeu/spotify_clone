import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/player/repository/local_playback_settings_repository.dart';
import 'package:spotify_clone/storage/key_value_store.dart';

class _FakeStore implements KeyValueStore {
  _FakeStore([Map<String, String>? seed]) : _store = {...?seed};

  final Map<String, String> _store;

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async => _store[key] = value;

  @override
  Future<void> delete(String key) async => _store.remove(key);
}

const _alice = 'alice@spotify.com';
const _bob = 'bob@spotify.com';

void main() {
  group('LocalPlaybackSettingsRepository', () {
    test('returns null when the account has never set a volume', () async {
      final repo = LocalPlaybackSettingsRepository(_FakeStore());
      expect(await repo.fetchVolume(_alice), isNull);
    });

    test('round-trips a saved volume', () async {
      final store = _FakeStore();
      final repo = LocalPlaybackSettingsRepository(store);

      await repo.saveVolume(_alice, 0.42);
      // A fresh instance reads it straight back from the store.
      expect(await LocalPlaybackSettingsRepository(store).fetchVolume(_alice), 0.42);
    });

    test('keeps each account\'s volume separate', () async {
      final store = _FakeStore();
      final repo = LocalPlaybackSettingsRepository(store);

      await repo.saveVolume(_alice, 0.2);
      await repo.saveVolume(_bob, 0.9);

      expect(await repo.fetchVolume(_alice), 0.2);
      expect(await repo.fetchVolume(_bob), 0.9);
    });

    test('clamps out-of-range values on the way in and out', () async {
      final store = _FakeStore();
      final repo = LocalPlaybackSettingsRepository(store);

      await repo.saveVolume(_alice, 1.8);
      expect(await repo.fetchVolume(_alice), 1.0);

      await repo.saveVolume(_bob, -0.5);
      expect(await repo.fetchVolume(_bob), 0.0);

      // A hand-edited out-of-range value is clamped on read too.
      final dirty = LocalPlaybackSettingsRepository(_FakeStore({'playback_volume:$_alice': '5'}));
      expect(await dirty.fetchVolume(_alice), 1.0);
    });

    test('treats an unparseable stored value as "no preference"', () async {
      final repo = LocalPlaybackSettingsRepository(_FakeStore({'playback_volume:$_alice': 'loud'}));
      expect(await repo.fetchVolume(_alice), isNull);
    });

    group('crossfade duration', () {
      test('returns null when the account has never set one', () async {
        final repo = LocalPlaybackSettingsRepository(_FakeStore());
        expect(await repo.fetchCrossfadeDuration(_alice), isNull);
      });

      test('round-trips per account', () async {
        final store = _FakeStore();
        final repo = LocalPlaybackSettingsRepository(store);

        await repo.saveCrossfadeDuration(_alice, const Duration(seconds: 8));
        await repo.saveCrossfadeDuration(_bob, const Duration(seconds: 3));

        final reloaded = LocalPlaybackSettingsRepository(store);
        expect(await reloaded.fetchCrossfadeDuration(_alice), const Duration(seconds: 8));
        expect(await reloaded.fetchCrossfadeDuration(_bob), const Duration(seconds: 3));
      });

      test('keeps an explicit "off" distinct from "never set"', () async {
        final store = _FakeStore();
        final repo = LocalPlaybackSettingsRepository(store);

        await repo.saveCrossfadeDuration(_alice, Duration.zero);

        // Zero means the account turned it off, which is not the same as null.
        expect(await repo.fetchCrossfadeDuration(_alice), Duration.zero);
        expect(await repo.fetchCrossfadeDuration(_bob), isNull);
      });

      test('normalises a negative duration to zero', () async {
        final store = _FakeStore();
        final repo = LocalPlaybackSettingsRepository(store);

        await repo.saveCrossfadeDuration(_alice, const Duration(seconds: -4));
        expect(await repo.fetchCrossfadeDuration(_alice), Duration.zero);
      });

      test('treats a corrupt stored value as "no preference"', () async {
        final repo = LocalPlaybackSettingsRepository(
          _FakeStore({'playback_crossfade_ms:$_alice': 'ages'}),
        );
        expect(await repo.fetchCrossfadeDuration(_alice), isNull);
      });
    });
  });
}
