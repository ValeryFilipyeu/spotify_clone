import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../catalog/models/track.dart';
import '../audio/audio_controller.dart';
import '../repository/playback_queue_repository.dart';
import '../repository/playback_settings_repository.dart';
import '../session/playback_audio_session.dart';
import '../session/media_session.dart';
import 'player_event.dart';
import 'player_state.dart';

/// Owns the playback queue and mirrors the [AudioController]'s streams into
/// state. App-wide and long-lived; it never navigates.
///
/// Every collaborator except [audioController] is optional: without them the
/// player works the same but forgets preferences and has no lock-screen
/// presence.
class PlayerBloc extends Bloc<PlayerEvent, PlayerState> {
  PlayerBloc({
    required AudioController audioController,
    PlaybackSettingsRepository? settingsRepository,
    PlaybackQueueRepository? queueRepository,
    Stream<String?>? userIdChanges,
    MediaSession? mediaSession,
    PlaybackAudioSession? audioSession,
    Random? random,
    // ignore_for_file: prefer_initializing_formals -- keeps public param names.
  }) : _audioController = audioController,
       _settingsRepository = settingsRepository,
       _queueRepository = queueRepository,
       _mediaSession = mediaSession ?? const NoopMediaSession(),
       _audioSession = audioSession ?? const NoopPlaybackAudioSession(),
       _random = random ?? Random(),
       super(const PlayerState()) {
    on<PlayerTrackStarted>(_onTrackStarted);
    on<PlayerPlayPauseToggled>(_onPlayPauseToggled);
    on<PlayerResumeRequested>((_, emit) => _resumeOrLoad(emit));
    on<PlayerPauseRequested>((_, _) => _pause());
    on<PlayerNextRequested>(_onNextRequested);
    on<PlayerPreviousRequested>(_onPreviousRequested);
    on<PlayerSeekRequested>(_onSeekRequested);
    on<PlayerStopped>(_onStopped);
    on<PlayerPositionTicked>(_onPositionTicked);
    on<PlayerDurationChanged>(_onDurationChanged);
    on<PlayerPlayingChanged>(_onPlayingChanged);
    on<PlayerBufferingChanged>(_onBufferingChanged);
    on<PlayerCompleted>(_onCompleted);
    on<PlayerShuffleToggled>(_onShuffleToggled);
    on<PlayerRepeatModeCycled>(_onRepeatModeCycled);
    on<PlayerVolumeChanged>(_onVolumeChanged);
    on<PlayerCrossfadeDurationChanged>(_onCrossfadeDurationChanged);
    on<PlayerQueueIndexSelected>(_onQueueIndexSelected);
    on<PlayerQueueReordered>(_onQueueReordered);
    on<PlayerQueueItemRemoved>(_onQueueItemRemoved);
    on<PlayerQueueAppended>(_onQueueAppended);
    on<PlayerPlayNextEnqueued>(_onPlayNextEnqueued);
    on<PlayerUserChanged>(_onUserChanged);
    on<PlayerInterruptionBegan>(_onInterruptionBegan);
    on<PlayerInterruptionEnded>(_onInterruptionEnded);
    on<PlayerOutputDisconnected>(_onOutputDisconnected);

    // Its own events, not a synthetic pause: resuming afterwards is only allowed
    // if the interruption is what stopped us. See [_pausedByInterruption].
    _interruptionSub = _audioSession.interruptions.listen((event) {
      add(switch (event) {
        AudioInterruptionBegan(:final duck) => PlayerInterruptionBegan(duck: duck),
        AudioInterruptionEnded(:final shouldResume) => PlayerInterruptionEnded(
          shouldResume: shouldResume,
        ),
        AudioOutputDisconnected() => const PlayerOutputDisconnected(),
      });
    });

    // Replays the current user on subscribe, so a restored session applies its
    // saved preferences at boot without an extra call.
    _userSub = userIdChanges?.listen((userId) => add(PlayerUserChanged(userId)));

    // The OS is just another remote control: a lock-screen tap and an in-app tap
    // take the same path.
    _sessionSub = _mediaSession.commands.listen((command) {
      add(switch (command) {
        MediaSessionPlayRequested() => const PlayerResumeRequested(),
        MediaSessionPauseRequested() => const PlayerPauseRequested(),
        MediaSessionNextRequested() => const PlayerNextRequested(),
        MediaSessionPreviousRequested() => const PlayerPreviousRequested(),
        MediaSessionStopRequested() => const PlayerStopped(),
        MediaSessionSeekRequested(:final position) => PlayerSeekRequested(position),
      });
    });

    // Position comes from our own ticker, not positionStream: on iOS just_audio
    // clamps it to the engine duration (reported as 0, so it pins to 0:00) and
    // on web it drifts off the wall clock.
    _durationSub = _audioController.durationStream.listen((d) {
      // iOS reports 0, which would clobber the duration seeded from the track.
      if (d != null && d > Duration.zero) add(PlayerDurationChanged(d));
    });
    _playingSub = _audioController.playingStream.listen((playing) {
      add(PlayerPlayingChanged(playing));
    });
    _bufferingSub = _audioController.bufferingStream.listen((b) {
      add(PlayerBufferingChanged(b));
    });
    _completedSub = _audioController.completedStream.listen((_) {
      add(const PlayerCompleted());
    });
  }

  static const _tick = Duration(milliseconds: 250);

  static const double _defaultVolume = 1;

  /// Collapses a whole slider drag into one write.
  static const _settingsSaveDelay = Duration(milliseconds: 400);

  /// Head start for buffering the next track, so the load lands before the fade
  /// window opens rather than inside it.
  static const _preloadLead = Duration(seconds: 8);

  final AudioController _audioController;
  final PlaybackSettingsRepository? _settingsRepository;
  final PlaybackQueueRepository? _queueRepository;
  final MediaSession _mediaSession;
  final PlaybackAudioSession _audioSession;

  /// Injectable so tests can seed a deterministic shuffle.
  final Random _random;

  late final StreamSubscription<Duration?> _durationSub;
  late final StreamSubscription<bool> _playingSub;
  late final StreamSubscription<bool> _bufferingSub;
  late final StreamSubscription<void> _completedSub;
  StreamSubscription<String?>? _userSub;
  StreamSubscription<MediaSessionCommand>? _sessionSub;
  StreamSubscription<AudioInterruption>? _interruptionSub;
  Timer? _ticker;

  static const double _duckFactor = 0.3;

  /// True only when the *interruption* paused us -- so "you can resume now" from
  /// the OS never restarts music the user paused themselves.
  bool _pausedByInterruption = false;

  /// Ducking is applied straight to the engine, leaving [PlayerState.volume] (the
  /// user's setting) alone so nothing is persisted and the slider stays put.
  bool _duckedByInterruption = false;

  /// Last snapshot handed to the OS, so four ticks a second are not four
  /// platform-channel round trips.
  String? _publishedSignature;

  /// The account whose volume is loaded, or null when signed out.
  String? _userId;

  /// A queue restored from disk that the engine has not been given yet. Loading
  /// it costs a round trip for audio nobody has asked to hear, so it waits for
  /// the first press of play. See [_resumeOrLoad].
  bool _needsLoad = false;

  /// Suppresses the save that restoring would otherwise trigger via [onChange].
  bool _restoring = false;

  int _ticksSinceSave = 0;

  /// Five seconds between position writes. At tick rate it would rewrite the
  /// whole preferences file 240 times a minute.
  static const int _saveEveryTicks = 20;

  /// Set while a crossfade is in flight: state has advanced but the outgoing
  /// track is still sounding.
  bool _isCrossfading = false;

  Timer? _settingsSaveTimer;

  /// Pending saves keyed by setting, so one slider's write never cancels
  /// another's. Each closure captures its own account id.
  final Map<String, Future<void> Function()> _pendingSaves = {};

  /// In [onChange] rather than in each handler, so none of the twenty-odd
  /// handlers can forget to publish or persist.
  @override
  void onChange(Change<PlayerState> change) {
    super.onChange(change);
    _publishNowPlaying(change);
    _rememberSession(change);
  }

  void _publishNowPlaying(Change<PlayerState> change) {
    final next = change.nextState;
    final track = next.currentTrack;
    if (track == null) {
      // Guarded so repeated empty states don't re-clear.
      if (_publishedSignature == null) return;
      _publishedSignature = null;
      unawaited(_mediaSession.clear().catchError((_) {}));
      return;
    }

    final nowPlaying = NowPlaying.from(next, track);
    // More than a tick, or backwards, means a seek or a track change -- which the
    // OS needs, or its extrapolated scrubber drifts away from ours.
    final jumped = (next.position - change.currentState.position).abs() > _tick * 2;
    if (nowPlaying.signature == _publishedSignature && !jumped) return;
    _publishedSignature = nowPlaying.signature;
    unawaited(_mediaSession.update(nowPlaying).catchError((_) {}));
  }

  Future<void> _onTrackStarted(PlayerTrackStarted event, Emitter<PlayerState> emit) async {
    await _startQueue(event.queue, event.startIndex, emit);
  }

  Future<void> _onPlayPauseToggled(PlayerPlayPauseToggled event, Emitter<PlayerState> emit) async {
    if (state.isPlaying) {
      _pause();
      return;
    }
    await _resumeOrLoad(emit);
  }

  /// Presses play, loading first if the engine holds no source -- the restored
  /// session case, where play() alone would silently do nothing.
  Future<void> _resumeOrLoad(Emitter<PlayerState> emit) async {
    if (!_needsLoad || !state.hasTrack) {
      _resume();
      return;
    }
    _pausedByInterruption = false;
    emit(state.copyWith(isLoading: true));
    await _playCurrent(emit, startAt: state.position);
  }

  // play()/pause() are never awaited: just_audio's play() future completes when
  // the track ENDS. isPlaying follows the engine's playingStream instead, so the
  // UI only ever shows what is real.
  //
  // Both transport methods clear _pausedByInterruption -- a deliberate press
  // supersedes anything the OS interrupted.

  void _resume() {
    _pausedByInterruption = false;
    if (!state.hasTrack) return;
    unawaited(_claimSessionThen(_audioController.play));
  }

  /// Claims the audio session before playing. Ordered: playing into a session we
  /// do not own mixes us under another app instead of interrupting it.
  Future<void> _claimSessionThen(Future<void> Function() play) async {
    await _audioSession.activate().catchError((_) {});
    await play().catchError((_) {});
  }

  void _pause() {
    _pausedByInterruption = false;
    if (!state.hasTrack) return;
    unawaited(_audioController.pause().catchError((_) {}));
  }

  /// Makes the engine agree with a state that says "not playing", where playback
  /// ended without anybody pressing pause (queue exhausted, load failed).
  ///
  /// `playing` is play *intent* and stays true when a source ends, so emitting
  /// `isPlaying: false` over it leaves the play button dead and the next track
  /// sounding under a transport frozen at 0:00. Awaited, unlike [_pause],
  /// because callers emit immediately afterwards.
  Future<void> _haltPlayback() => _audioController.pause().catchError((_) {});

  void _onInterruptionBegan(PlayerInterruptionBegan event, Emitter<PlayerState> emit) {
    if (!state.hasTrack) return;

    if (event.duck) {
      // Keep playing, just get out of the way.
      if (_duckedByInterruption) return;
      _duckedByInterruption = true;
      unawaited(_audioController.setVolume(state.volume * _duckFactor).catchError((_) {}));
      return;
    }

    // Nothing to take away, and nothing to restore later.
    if (!state.isPlaying) return;
    _pause();
    _pausedByInterruption = true;
  }

  void _onInterruptionEnded(PlayerInterruptionEnded event, Emitter<PlayerState> emit) {
    if (_duckedByInterruption) {
      _duckedByInterruption = false;
      unawaited(_audioController.setVolume(state.volume).catchError((_) {}));
    }
    // Resume only what we stopped, and only when the platform says it is welcome.
    if (!_pausedByInterruption) return;
    if (event.shouldResume) {
      _resume();
    } else {
      _pausedByInterruption = false;
    }
  }

  void _onOutputDisconnected(PlayerOutputDisconnected event, Emitter<PlayerState> emit) {
    // _pause() clears _pausedByInterruption: unplugged headphones must never
    // lead to music resuming out of the speaker.
    _pause();
  }

  Future<void> _onNextRequested(PlayerNextRequested event, Emitter<PlayerState> emit) async {
    if (!state.hasTrack) return;
    if (state.currentIndex < state.queue.length - 1) {
      await _goTo(state.currentIndex + 1, emit);
    } else if (state.repeatMode == PlayerRepeatMode.all && state.queue.length > 1) {
      // Repeat-one deliberately does not trap Next; it always moves on.
      await _goTo(0, emit);
    }
  }

  Future<void> _onPreviousRequested(
    PlayerPreviousRequested event,
    Emitter<PlayerState> emit,
  ) async {
    if (!state.hasTrack) return;
    if (state.currentIndex > 0) {
      await _goTo(state.currentIndex - 1, emit);
    } else if (state.repeatMode == PlayerRepeatMode.all && state.queue.length > 1) {
      await _goTo(state.queue.length - 1, emit);
    }
  }

  Future<void> _onSeekRequested(PlayerSeekRequested event, Emitter<PlayerState> emit) async {
    // Before the async seek, not after: on release the scrubber falls back to
    // state.position, so emitting late makes the thumb snap back for a frame.
    emit(state.copyWith(position: event.position));
    // Nothing loaded to seek; the eventual load starts from here instead.
    if (_needsLoad) return;
    await _audioController.seek(event.position);
  }

  Future<void> _onStopped(PlayerStopped event, Emitter<PlayerState> emit) async {
    await _audioController.stop();
    // Hand the device back so whatever we interrupted can carry on.
    await _audioSession.deactivate().catchError((_) {});
    emit(_clearedState());
  }

  Future<void> _onPositionTicked(PlayerPositionTicked event, Emitter<PlayerState> emit) async {
    // `playing` stays true across a track boundary, so without the isLoading
    // guard the scrubber moves before the next track is audible.
    if (!state.isPlaying || state.isLoading) return;
    final next = state.position + _tick;
    final capped = state.duration > Duration.zero && next > state.duration ? state.duration : next;
    emit(state.copyWith(position: capped));

    if (++_ticksSinceSave >= _saveEveryTicks) {
      _ticksSinceSave = 0;
      _savePosition(state);
    }

    // The ticker doubles as the crossfade trigger: it is the only thing that
    // knows how close the track is to its end.
    _maybePreloadNext(capped);
    if (!_shouldStartCrossfade(capped)) return;
    final upcoming = _nextIndexOnCompletion();
    if (upcoming == null) return;
    await _crossfadeTo(upcoming, emit);
  }

  /// Buffers the next track *before* the fade window opens. A load inside the
  /// fade eats the overlap, which looks exactly like crossfade not working.
  ///
  /// Conditions mirror [_shouldStartCrossfade], so nothing is buffered that is
  /// not going to be faded in.
  void _maybePreloadNext(Duration position) {
    if (_isCrossfading) return;
    final fade = state.crossfadeDuration;
    if (fade <= Duration.zero) return;
    if (!_audioController.supportsCrossfade) return;
    final duration = state.duration;
    if (duration <= fade * 2) return; // changes over on a cut, nothing to fade
    if (position < duration - fade - _preloadLead) return;

    final upcoming = _nextIndexOnCompletion();
    if (upcoming == null) return; // nothing follows; nothing to buffer
    // Runs every tick in the window; the controller dedupes by url.
    unawaited(_audioController.preload(state.queue[upcoming].audioUrl).catchError((_) {}));
  }

  /// Whether the next track should now be fading in underneath this one.
  bool _shouldStartCrossfade(Duration position) {
    if (_isCrossfading) return false; // one already in flight
    final fade = state.crossfadeDuration;
    if (fade <= Duration.zero) return false;
    if (!_audioController.supportsCrossfade) return false;

    final duration = state.duration;
    // A track not comfortably longer than the fade gets a plain cut -- and this
    // is what stops a short track skipping on every tick.
    if (duration <= fade * 2) return false;

    // A cooldown, since starting a crossfade resets position to zero.
    if (position < fade) return false;

    return position >= duration - fade;
  }

  /// Where playback goes when the track finishes, or null if it should stop.
  /// Shared by completion and the crossfade trigger so they cannot disagree.
  int? _nextIndexOnCompletion() {
    final isLast = state.currentIndex >= state.queue.length - 1;
    return switch (state.repeatMode) {
      PlayerRepeatMode.one => state.currentIndex,
      PlayerRepeatMode.all => isLast ? 0 : state.currentIndex + 1,
      PlayerRepeatMode.off => isLast ? null : state.currentIndex + 1,
    };
  }

  /// Moves to [index] overlapping the outgoing track. No isLoading: the point of
  /// a crossfade is that nothing visibly stalls.
  Future<void> _crossfadeTo(int index, Emitter<PlayerState> emit) async {
    final track = state.queue[index];
    emit(state.copyWith(currentIndex: index, position: Duration.zero, duration: track.duration));
    // State has advanced but the load has not landed: nothing else may advance.
    _isCrossfading = true;
    try {
      final duration = await _audioController.crossfadeTo(
        track.audioUrl,
        fade: state.crossfadeDuration,
      );
      // Next during the load supersedes us; a stale duration would put the fade
      // window somewhere unreachable.
      if (state.currentTrack?.id != track.id) return;
      if (duration != null && duration > Duration.zero) emit(state.copyWith(duration: duration));
    } catch (_) {
      await _haltPlayback();
      emit(state.copyWith(isLoading: false, isPlaying: false));
    } finally {
      _isCrossfading = false;
    }
  }

  void _onDurationChanged(PlayerDurationChanged event, Emitter<PlayerState> emit) {
    emit(state.copyWith(duration: event.duration));
  }

  void _onPlayingChanged(PlayerPlayingChanged event, Emitter<PlayerState> emit) {
    // isLoading comes from bufferingStream, not from here: `playing` stays true
    // across a track boundary.
    emit(state.copyWith(isPlaying: event.isPlaying));
    if (event.isPlaying) {
      _ticker ??= Timer.periodic(_tick, (_) => add(const PlayerPositionTicked()));
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  void _onBufferingChanged(PlayerBufferingChanged event, Emitter<PlayerState> emit) {
    emit(state.copyWith(isLoading: event.isBuffering));
  }

  Future<void> _onCompleted(PlayerCompleted event, Emitter<PlayerState> emit) async {
    // A crossfade already advanced us; the outgoing track ending is old news.
    if (_isCrossfading) return;

    final upcoming = _nextIndexOnCompletion();
    if (upcoming == null) {
      await _haltPlayback();
      // After the pause, strictly: seeking while the engine still holds play
      // intent just carries on from the new position.
      await _audioController.seek(Duration.zero).catchError((_) {});
      emit(state.copyWith(isPlaying: false, position: Duration.zero));
      return;
    }
    // A fresh load even for repeat-one: one code path, verified on all four
    // platforms.
    await _goTo(upcoming, emit);
  }

  // --- Shuffle / repeat / volume ---

  void _onShuffleToggled(PlayerShuffleToggled event, Emitter<PlayerState> emit) {
    // Order only, never the audio: the playing track just moves index.
    if (!state.hasTrack) {
      emit(state.copyWith(isShuffled: !state.isShuffled));
      return;
    }

    if (state.isShuffled) {
      final restored = _restoredOrder();
      final current = state.currentTrack!;
      final index = restored.indexWhere((t) => t.id == current.id);
      emit(state.copyWith(isShuffled: false, queue: restored, currentIndex: index < 0 ? 0 : index));
    } else {
      emit(
        state.copyWith(
          isShuffled: true,
          queue: _shuffledFrom(state.queue, state.currentIndex),
          // The current track is moved to the front of the shuffled order.
          currentIndex: 0,
        ),
      );
    }
  }

  void _onRepeatModeCycled(PlayerRepeatModeCycled event, Emitter<PlayerState> emit) {
    final next = switch (state.repeatMode) {
      PlayerRepeatMode.off => PlayerRepeatMode.all,
      PlayerRepeatMode.all => PlayerRepeatMode.one,
      PlayerRepeatMode.one => PlayerRepeatMode.off,
    };
    emit(state.copyWith(repeatMode: next));
  }

  Future<void> _onVolumeChanged(PlayerVolumeChanged event, Emitter<PlayerState> emit) async {
    final volume = event.volume.clamp(0.0, 1.0);
    emit(state.copyWith(volume: volume));
    await _audioController.setVolume(volume).catchError((_) {});

    final userId = _userId;
    final repository = _settingsRepository;
    if (userId != null && repository != null) {
      _scheduleSave('volume', () => repository.saveVolume(userId, volume));
    }
  }

  Future<void> _onCrossfadeDurationChanged(
    PlayerCrossfadeDurationChanged event,
    Emitter<PlayerState> emit,
  ) async {
    final duration = event.duration.isNegative
        ? Duration.zero
        : (event.duration > PlayerState.maxCrossfadeDuration
              ? PlayerState.maxCrossfadeDuration
              : event.duration);
    emit(state.copyWith(crossfadeDuration: duration));

    final userId = _userId;
    final repository = _settingsRepository;
    if (userId != null && repository != null) {
      _scheduleSave('crossfade', () => repository.saveCrossfadeDuration(userId, duration));
    }
  }

  /// Loads (or clears) the signed-in account's playback preferences.
  Future<void> _onUserChanged(PlayerUserChanged event, Emitter<PlayerState> emit) async {
    if (event.userId == _userId) return;

    // A half-dragged preference belongs to the outgoing account.
    await _flushSaves();
    _userId = event.userId;

    final userId = event.userId;
    final repository = _settingsRepository;
    // Signed out: don't leak preferences to whoever signs in next.
    final volume = userId == null
        ? _defaultVolume
        : await repository?.fetchVolume(userId) ?? _defaultVolume;
    final crossfade = userId == null
        ? Duration.zero
        : await repository?.fetchCrossfadeDuration(userId) ?? Duration.zero;

    final restored = userId == null ? null : await _queueRepository?.fetchQueue(userId);

    _restoring = true;
    emit(
      restored == null
          ? state.copyWith(volume: volume, crossfadeDuration: crossfade)
          : state.copyWith(
              volume: volume,
              crossfadeDuration: crossfade,
              queue: restored.queue,
              sourceQueue: restored.effectiveSourceQueue,
              currentIndex: restored.currentIndex,
              position: restored.position,
              // The engine has no duration until play, so the scrubber needs
              // this to have a scale at all.
              duration: restored.queue[restored.currentIndex].duration,
              isShuffled: restored.isShuffled,
              isPlaying: false,
              isLoading: false,
            ),
    );
    _restoring = false;
    // Nothing has been handed to the audio engine. See [_needsLoad].
    _needsLoad = restored != null;

    await _audioController.setVolume(volume).catchError((_) {});
  }

  /// Writes the session down when it changes. In [onChange] because the queue is
  /// edited from six handlers and any of them could forget.
  void _rememberSession(Change<PlayerState> change) {
    if (_restoring) return;
    final previous = change.currentState;
    final next = change.nextState;

    if (next.queue.isEmpty) {
      // A dismissed queue must not come back at the next launch.
      if (previous.queue.isNotEmpty) _clearSession();
      return;
    }

    // By identity: copyWith passes the same list along when the queue is
    // untouched, so this is exact and costs nothing at tick rate.
    if (!identical(previous.queue, next.queue) || previous.isShuffled != next.isShuffled) {
      _saveQueue(next);
    } else if (previous.currentIndex != next.currentIndex) {
      _savePosition(next);
    }
  }

  void _saveQueue(PlayerState state) {
    final userId = _userId;
    final repository = _queueRepository;
    if (userId == null || repository == null) return;

    final saved = SavedQueue(
      queue: state.queue,
      // Only when it is actually a different order -- see [SavedQueue].
      sourceQueue: listEquals(state.queue, state.sourceQueue) ? null : state.sourceQueue,
      isShuffled: state.isShuffled,
    );
    _scheduleSave('queue', () => repository.saveQueue(userId, saved));
    _savePosition(state);
  }

  void _savePosition(PlayerState state) {
    final userId = _userId;
    final repository = _queueRepository;
    if (userId == null || repository == null || !state.hasTrack) return;

    final index = state.currentIndex;
    final position = state.position;
    _scheduleSave(
      'position',
      () => repository.savePosition(userId, currentIndex: index, position: position),
    );
  }

  void _clearSession() {
    final userId = _userId;
    final repository = _queueRepository;
    if (userId == null || repository == null) return;
    _scheduleSave('queue', () => repository.clear(userId));
    _pendingSaves.remove('position');
  }

  void _scheduleSave(String key, Future<void> Function() save) {
    _pendingSaves[key] = save; // latest write for this setting wins
    _settingsSaveTimer?.cancel();
    _settingsSaveTimer = Timer(_settingsSaveDelay, () => unawaited(_flushSaves()));
  }

  /// Flushes pending saves: on debounce, on account switch, and on close.
  Future<void> _flushSaves() async {
    _settingsSaveTimer?.cancel();
    _settingsSaveTimer = null;
    if (_pendingSaves.isEmpty) return;
    final saves = List.of(_pendingSaves.values);
    _pendingSaves.clear();
    for (final save in saves) {
      try {
        await save();
      } catch (_) {
        // A failed preference write must never break playback.
      }
    }
  }

  // --- Queue editing ---

  Future<void> _onQueueIndexSelected(
    PlayerQueueIndexSelected event,
    Emitter<PlayerState> emit,
  ) async {
    if (event.index < 0 || event.index >= state.queue.length) return;
    if (event.index == state.currentIndex) return; // already playing it
    await _goTo(event.index, emit);
  }

  void _onQueueReordered(PlayerQueueReordered event, Emitter<PlayerState> emit) {
    final length = state.queue.length;
    if (event.oldIndex < 0 || event.oldIndex >= length) return;
    if (event.newIndex < 0 || event.newIndex >= length) return;
    if (event.oldIndex == event.newIndex) return;

    final queue = [...state.queue];
    queue.insert(event.newIndex, queue.removeAt(event.oldIndex));

    // Follow the current track to its new index rather than keeping the number.
    var index = state.currentIndex;
    if (event.oldIndex == index) {
      index = event.newIndex;
    } else {
      if (event.oldIndex < index) index--;
      if (event.newIndex <= index) index++;
    }

    // No _playCurrent here -- reordering must never restart the audio.
    emit(state.copyWith(queue: queue, currentIndex: index));
  }

  Future<void> _onQueueItemRemoved(PlayerQueueItemRemoved event, Emitter<PlayerState> emit) async {
    if (event.index < 0 || event.index >= state.queue.length) return;

    final queue = [...state.queue]..removeAt(event.index);
    if (queue.isEmpty) {
      await _audioController.stop();
      emit(_clearedState());
      return;
    }

    if (event.index < state.currentIndex) {
      emit(state.copyWith(queue: queue, currentIndex: state.currentIndex - 1));
    } else if (event.index > state.currentIndex) {
      emit(state.copyWith(queue: queue));
    } else {
      // The playing track went: whatever shifted into its slot takes over.
      final next = event.index > queue.length - 1 ? queue.length - 1 : event.index;
      emit(state.copyWith(queue: queue, currentIndex: next));
      await _goTo(next, emit);
    }
  }

  Future<void> _onQueueAppended(PlayerQueueAppended event, Emitter<PlayerState> emit) async {
    if (!state.hasTrack) {
      await _startQueue([event.track], 0, emit);
      return;
    }
    emit(state.copyWith(queue: [...state.queue, event.track]));
  }

  Future<void> _onPlayNextEnqueued(PlayerPlayNextEnqueued event, Emitter<PlayerState> emit) async {
    if (!state.hasTrack) {
      await _startQueue([event.track], 0, emit);
      return;
    }
    final queue = [...state.queue]..insert(state.currentIndex + 1, event.track);
    emit(state.copyWith(queue: queue));
  }

  // --- Helpers ---

  /// Loads [source] and plays [startIndex]. With shuffle already on, the picked
  /// track plays first and the rest are randomised behind it.
  Future<void> _startQueue(List<Track> source, int startIndex, Emitter<PlayerState> emit) async {
    if (source.isEmpty) return;
    final start = startIndex.clamp(0, source.length - 1);
    final shuffled = state.isShuffled;
    final queue = shuffled ? _shuffledFrom(source, start) : source;
    final index = shuffled ? 0 : start;

    emit(
      state.copyWith(
        queue: queue,
        sourceQueue: source,
        currentIndex: index,
        isLoading: true,
        position: Duration.zero,
        // iOS never reports a real duration, so on that platform this seed is
        // the only scale the timeline ever gets.
        duration: queue[index].duration,
      ),
    );
    await _playCurrent(emit);
  }

  /// Moves to [index] and (re)loads its audio.
  Future<void> _goTo(int index, Emitter<PlayerState> emit) async {
    emit(
      state.copyWith(
        currentIndex: index,
        isLoading: true,
        position: Duration.zero,
        duration: state.queue[index].duration,
      ),
    );
    await _playCurrent(emit);
  }

  /// [source] with [keepFirst] moved to the front, the rest randomised. By
  /// index, not by id, so duplicates from "Add to queue" survive.
  List<Track> _shuffledFrom(List<Track> source, int keepFirst) {
    final rest = [...source]..removeAt(keepFirst);
    rest.shuffle(_random);
    return [source[keepFirst], ...rest];
  }

  /// The queue back in [PlayerState.sourceQueue]'s order, with anything added
  /// since appended in its current order so un-shuffling never drops it.
  List<Track> _restoredOrder() {
    final rank = <String, int>{};
    for (var i = 0; i < state.sourceQueue.length; i++) {
      rank.putIfAbsent(state.sourceQueue[i].id, () => i);
    }
    final fromSource = <Track>[];
    final added = <Track>[];
    for (final track in state.queue) {
      (rank.containsKey(track.id) ? fromSource : added).add(track);
    }
    fromSource.sort((a, b) => rank[a.id]!.compareTo(rank[b.id]!));
    return [...fromSource, ...added];
  }

  /// An empty player that keeps preferences: dismissing the queue is a session
  /// reset, not a preferences reset.
  PlayerState _clearedState() => PlayerState(
    isShuffled: state.isShuffled,
    repeatMode: state.repeatMode,
    volume: state.volume,
    crossfadeDuration: state.crossfadeDuration,
  );

  Future<void> _playCurrent(Emitter<PlayerState> emit, {Duration? startAt}) async {
    final track = state.currentTrack;
    if (track == null) return;
    _needsLoad = false;
    // Claim the device before loading, so we take it from whatever else is
    // playing rather than mixing underneath it.
    await _audioSession.activate().catchError((_) {});
    try {
      final duration = await _audioController.setUrl(track.audioUrl);
      // A newer track change overtook this load and now owns the player.
      if (state.currentTrack?.id != track.id) return;
      // Never let iOS's 0 replace the seeded duration.
      if (duration != null && duration > Duration.zero) emit(state.copyWith(duration: duration));
      // Web rebuilds the underlying player on a source switch, resetting volume.
      if (state.volume != 1) await _audioController.setVolume(state.volume).catchError((_) {});
      // Before play(), so a restored track does not sound from the top first.
      if (startAt != null && startAt > Duration.zero) {
        await _audioController.seek(startAt).catchError((_) {});
      }
    } catch (_) {
      // Nothing will sound, but the engine may still hold play intent.
      await _haltPlayback();
      emit(state.copyWith(isLoading: false, isPlaying: false));
      return;
    }
    unawaited(_audioController.play().catchError((_) {}));
  }

  @override
  Future<void> close() async {
    _ticker?.cancel();
    await _flushSaves(); // don't lose a change inside the debounce window
    await _sessionSub?.cancel();
    await _interruptionSub?.cancel();
    await _userSub?.cancel();
    await _durationSub.cancel();
    await _playingSub.cancel();
    await _bufferingSub.cancel();
    await _completedSub.cancel();
    await _audioController.dispose();
    return super.close();
  }
}
