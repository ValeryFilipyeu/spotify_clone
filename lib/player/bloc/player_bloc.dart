import 'dart:async';
import 'dart:math';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../catalog/models/track.dart';
import '../audio/audio_controller.dart';
import '../repository/playback_settings_repository.dart';
import 'player_event.dart';
import 'player_state.dart';

/// App-wide, one instance for the whole app lifetime (like AuthBloc). Owns the
/// playback queue and mirrors the [AudioController]'s streams into state so the
/// mini-player and full player can both react. It never navigates.
///
/// [settingsRepository] and [userIdChanges] are optional: supply both (as the
/// app does) and volume is persisted per account; omit them and the player
/// behaves identically with an in-memory volume.
class PlayerBloc extends Bloc<PlayerEvent, PlayerState> {
  PlayerBloc({
    required AudioController audioController,
    PlaybackSettingsRepository? settingsRepository,
    Stream<String?>? userIdChanges,
    Random? random,
        // ignore_for_file: prefer_initializing_formals -- keeps public param names.
  })  : _audioController = audioController,
        _settingsRepository = settingsRepository,
        _random = random ?? Random(),
        super(const PlayerState()) {
    on<PlayerTrackStarted>(_onTrackStarted);
    on<PlayerPlayPauseToggled>(_onPlayPauseToggled);
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
    on<PlayerQueueIndexSelected>(_onQueueIndexSelected);
    on<PlayerQueueReordered>(_onQueueReordered);
    on<PlayerQueueItemRemoved>(_onQueueItemRemoved);
    on<PlayerQueueAppended>(_onQueueAppended);
    on<PlayerPlayNextEnqueued>(_onPlayNextEnqueued);
    on<PlayerUserChanged>(_onUserChanged);

    // Volume is stored per account, so the player has to know who is signed in.
    // The stream replays the current user on subscribe, so a restored session
    // applies its saved level at boot without any extra call.
    _userSub = userIdChanges?.listen((userId) => add(PlayerUserChanged(userId)));

    // We drive `position` from our own wall-clock ticker (see _onPlayingChanged
    // / _onPositionTicked), NOT from audioController.positionStream. just_audio
    // has no usable position source that works on every platform: on iOS it
    // clamps position to the engine duration (which iOS reports as 0, pinning
    // it to 0:00), and on web its position getter interpolates off the wall
    // clock while the audio-element `timeupdate` handler is a no-op -- so its
    // stream either freezes or drifts. The ticker is smooth and consistent.
    _durationSub = _audioController.durationStream.listen((d) {
      // Ignore null and 0 -- iOS reports duration as Duration.zero, which
      // would clobber the seeded track duration.
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

  /// The volume every account starts at until it saves its own.
  static const double _defaultVolume = 1;

  /// The volume slider fires on every drag frame; this collapses a whole
  /// gesture into a single write (the same debounce idea as SearchCubit).
  static const _volumeSaveDelay = Duration(milliseconds: 400);

  final AudioController _audioController;
  final PlaybackSettingsRepository? _settingsRepository;

  /// Injectable so tests can seed a deterministic shuffle.
  final Random _random;

  late final StreamSubscription<Duration?> _durationSub;
  late final StreamSubscription<bool> _playingSub;
  late final StreamSubscription<bool> _bufferingSub;
  late final StreamSubscription<void> _completedSub;
  StreamSubscription<String?>? _userSub;
  Timer? _ticker;

  /// The account whose volume is loaded, or null when signed out.
  String? _userId;

  Timer? _volumeSaveTimer;

  /// The not-yet-written volume save, captured with the account it belongs to so
  /// a mid-gesture account switch still persists to the right one.
  Future<void> Function()? _pendingVolumeSave;

  Future<void> _onTrackStarted(PlayerTrackStarted event, Emitter<PlayerState> emit) async {
    await _startQueue(event.queue, event.startIndex, emit);
  }

  void _onPlayPauseToggled(PlayerPlayPauseToggled event, Emitter<PlayerState> emit) {
    if (!state.hasTrack) return;
    // Fire-and-forget: play()/pause() are not awaited. just_audio's play()
    // future completes when the track ENDS, so awaiting it would block the
    // handler for the whole track -- which on web interleaves badly with the
    // position/buffering event stream. play() resumes from the paused
    // position on its own.
    if (state.isPlaying) {
      unawaited(_audioController.pause().catchError((_) {}));
    } else {
      unawaited(_audioController.play().catchError((_) {}));
    }
  }

  Future<void> _onNextRequested(PlayerNextRequested event, Emitter<PlayerState> emit) async {
    if (!state.hasTrack) return;
    if (state.currentIndex < state.queue.length - 1) {
      await _goTo(state.currentIndex + 1, emit);
    } else if (state.repeatMode == PlayerRepeatMode.all && state.queue.length > 1) {
      // Wrap to the front. (Repeat-one deliberately does NOT trap the Next
      // button -- pressing Next always moves on, as in Spotify.)
      await _goTo(0, emit);
    }
  }

  Future<void> _onPreviousRequested(PlayerPreviousRequested event, Emitter<PlayerState> emit) async {
    if (!state.hasTrack) return;
    if (state.currentIndex > 0) {
      await _goTo(state.currentIndex - 1, emit);
    } else if (state.repeatMode == PlayerRepeatMode.all && state.queue.length > 1) {
      await _goTo(state.queue.length - 1, emit);
    }
  }

  Future<void> _onSeekRequested(PlayerSeekRequested event, Emitter<PlayerState> emit) async {
    // Reflect the target position IMMEDIATELY, before the (async) engine seek.
    // On release the scrubber drops its local drag value and falls back to
    // state.position; if we emitted only after the await, the thumb would snap
    // back to the pre-seek position for a frame and then jump to the target --
    // a visible flicker. Emitting first makes the thumb stay put.
    emit(state.copyWith(position: event.position));
    await _audioController.seek(event.position);
  }

  Future<void> _onStopped(PlayerStopped event, Emitter<PlayerState> emit) async {
    await _audioController.stop();
    emit(_clearedState());
  }

  void _onPositionTicked(PlayerPositionTicked event, Emitter<PlayerState> emit) {
    // Don't advance while a (new) track is still buffering -- on auto-advance
    // just_audio keeps `playing` true across the track boundary, so without
    // this guard the scrubber would move before the next track's audio has
    // actually started.
    if (!state.isPlaying || state.isLoading) return;
    final next = state.position + _tick;
    // Cap at the (known) duration so the thumb never runs past the end.
    final capped = state.duration > Duration.zero && next > state.duration ? state.duration : next;
    emit(state.copyWith(position: capped));
  }

  void _onDurationChanged(PlayerDurationChanged event, Emitter<PlayerState> emit) {
    emit(state.copyWith(duration: event.duration));
  }

  void _onPlayingChanged(PlayerPlayingChanged event, Emitter<PlayerState> emit) {
    // isLoading is driven by bufferingStream, NOT by this -- just_audio's
    // `playing` stays true across a track boundary, so it can't tell us when
    // the next track has finished loading.
    emit(state.copyWith(isPlaying: event.isPlaying));
    // Drive the wall-clock position ticker off play/pause. (See the note in the
    // constructor for why we use a ticker instead of the engine's position.)
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
    switch (state.repeatMode) {
      case PlayerRepeatMode.one:
        // Reload the same track rather than seek(0)+play(): every other
        // track-change path here goes through _playCurrent, and a fresh load is
        // the one behaviour we've verified on all four platforms.
        await _goTo(state.currentIndex, emit);
      case PlayerRepeatMode.all:
        await _goTo(state.currentIndex < state.queue.length - 1 ? state.currentIndex + 1 : 0, emit);
      case PlayerRepeatMode.off:
        if (state.currentIndex < state.queue.length - 1) {
          await _goTo(state.currentIndex + 1, emit);
        } else {
          emit(state.copyWith(isPlaying: false, position: Duration.zero));
        }
    }
  }

  // --- Shuffle / repeat / volume ---

  void _onShuffleToggled(PlayerShuffleToggled event, Emitter<PlayerState> emit) {
    // Only the queue ORDER changes here -- never the audio. The track that is
    // playing keeps playing; we just move it to its new index.
    if (!state.hasTrack) {
      emit(state.copyWith(isShuffled: !state.isShuffled));
      return;
    }

    if (state.isShuffled) {
      final restored = _restoredOrder();
      final current = state.currentTrack!;
      final index = restored.indexWhere((t) => t.id == current.id);
      emit(state.copyWith(
        isShuffled: false,
        queue: restored,
        currentIndex: index < 0 ? 0 : index,
      ));
    } else {
      emit(state.copyWith(
        isShuffled: true,
        queue: _shuffledFrom(state.queue, state.currentIndex),
        // The current track is moved to the front of the shuffled order.
        currentIndex: 0,
      ));
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
    _scheduleVolumeSave(volume);
  }

  /// Loads (or clears) the signed-in account's playback preferences.
  Future<void> _onUserChanged(PlayerUserChanged event, Emitter<PlayerState> emit) async {
    if (event.userId == _userId) return;

    // Any half-typed volume still belongs to the OUTGOING account -- write it
    // before switching, since the pending save captured that account's id.
    await _flushVolumeSave();
    _userId = event.userId;

    final userId = event.userId;
    // Signed out: forget this account's level rather than leaking it to whoever
    // signs in next.
    final volume = userId == null
        ? _defaultVolume
        : await _settingsRepository?.fetchVolume(userId) ?? _defaultVolume;

    emit(state.copyWith(volume: volume));
    await _audioController.setVolume(volume).catchError((_) {});
  }

  void _scheduleVolumeSave(double volume) {
    final userId = _userId;
    final repository = _settingsRepository;
    if (userId == null || repository == null) return; // nothing to persist to

    _volumeSaveTimer?.cancel();
    _pendingVolumeSave = () => repository.saveVolume(userId, volume);
    _volumeSaveTimer = Timer(_volumeSaveDelay, () => unawaited(_flushVolumeSave()));
  }

  /// Writes the pending volume immediately, if any. Called when the debounce
  /// elapses, on account switch, and on close -- so a save is never lost.
  Future<void> _flushVolumeSave() async {
    _volumeSaveTimer?.cancel();
    _volumeSaveTimer = null;
    final pending = _pendingVolumeSave;
    _pendingVolumeSave = null;
    if (pending == null) return;
    try {
      await pending();
    } catch (_) {
      // A failed preference write must never break playback.
    }
  }

  // --- Queue editing ---

  Future<void> _onQueueIndexSelected(PlayerQueueIndexSelected event, Emitter<PlayerState> emit) async {
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

    // Keep the SAME track current by tracking where it ends up: the moved item
    // lands on newIndex, otherwise the removal shifts it left and the insertion
    // shifts it right.
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
      // The playing track was removed: whatever shifted into its slot takes
      // over (or the new last track, if we removed the tail).
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

  /// Loads [source] as a new queue and starts playing [startIndex]. When
  /// shuffle is already on, the picked track plays first and the rest are
  /// randomised behind it (matching what Spotify does).
  Future<void> _startQueue(List<Track> source, int startIndex, Emitter<PlayerState> emit) async {
    if (source.isEmpty) return;
    final start = startIndex.clamp(0, source.length - 1);
    final shuffled = state.isShuffled;
    final queue = shuffled ? _shuffledFrom(source, start) : source;
    final index = shuffled ? 0 : start;

    emit(state.copyWith(
      queue: queue,
      sourceQueue: source,
      currentIndex: index,
      isLoading: true,
      position: Duration.zero,
      // Seed from the track's known duration so the scrubber has a scale
      // immediately. On iOS the audio engine reports duration as 0 (never the
      // real value), so this seed is what the timeline relies on there; on
      // Android/web the engine's real duration overrides it (see below).
      duration: queue[index].duration,
    ));
    await _playCurrent(emit);
  }

  /// Moves to [index] and (re)loads its audio.
  Future<void> _goTo(int index, Emitter<PlayerState> emit) async {
    emit(state.copyWith(
      currentIndex: index,
      isLoading: true,
      position: Duration.zero,
      duration: state.queue[index].duration,
    ));
    await _playCurrent(emit);
  }

  /// [source] with the track at [keepFirst] moved to the front and everything
  /// else randomised. Removing by index (not by id) keeps duplicate entries --
  /// legal, via "Add to queue" -- intact.
  List<Track> _shuffledFrom(List<Track> source, int keepFirst) {
    final rest = [...source]..removeAt(keepFirst);
    rest.shuffle(_random);
    return [source[keepFirst], ...rest];
  }

  /// The queue back in [PlayerState.sourceQueue]'s order. Tracks added to the
  /// queue since it started (which sourceQueue never saw) keep their current
  /// relative order at the end, so un-shuffling never drops them.
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

  /// An empty player that keeps the user's playback preferences. Clearing the
  /// queue (dismissing the player, or removing its last entry) is a session
  /// reset, not a preferences reset.
  PlayerState _clearedState() => PlayerState(
        isShuffled: state.isShuffled,
        repeatMode: state.repeatMode,
        volume: state.volume,
      );

  Future<void> _playCurrent(Emitter<PlayerState> emit) async {
    final track = state.currentTrack;
    if (track == null) return;
    try {
      // setUrl returns the duration when the engine knows it at load time.
      final duration = await _audioController.setUrl(track.audioUrl);
      // Only override the seeded duration with a real engine value (iOS
      // returns 0 here).
      if (duration != null && duration > Duration.zero) emit(state.copyWith(duration: duration));
      // Re-assert volume: on web the source switch above tears down and rebuilds
      // the underlying player (see JustAudioController.setUrl), which would
      // otherwise silently reset it to full.
      if (state.volume != 1) await _audioController.setVolume(state.volume).catchError((_) {});
    } catch (e) {
      emit(state.copyWith(isLoading: false, isPlaying: false));
      return;
    }
    // Fire-and-forget (see _onPlayPauseToggled): play() completes on track
    // END, so it must not be awaited here. Completion is handled via
    // completedStream; playing/loading via the playing/buffering streams.
    unawaited(_audioController.play().catchError((_) {}));
  }

  @override
  Future<void> close() async {
    _ticker?.cancel();
    // Don't lose a volume change made within the debounce window.
    await _flushVolumeSave();
    await _userSub?.cancel();
    await _durationSub.cancel();
    await _playingSub.cancel();
    await _bufferingSub.cancel();
    await _completedSub.cancel();
    await _audioController.dispose();
    return super.close();
  }
}
