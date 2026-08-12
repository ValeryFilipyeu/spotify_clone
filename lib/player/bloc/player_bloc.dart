import 'dart:async';
import 'dart:math';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../catalog/models/track.dart';
import '../audio/audio_controller.dart';
import '../repository/playback_settings_repository.dart';
import '../session/playback_audio_session.dart';
import '../session/media_session.dart';
import 'player_event.dart';
import 'player_state.dart';

/// App-wide, one instance for the whole app lifetime (like AuthBloc). Owns the
/// playback queue and mirrors the [AudioController]'s streams into state so the
/// mini-player and full player can both react. It never navigates.
///
/// [settingsRepository] and [userIdChanges] are optional: supply both (as the
/// app does) and volume is persisted per account; omit them and the player
/// behaves identically with an in-memory volume. [mediaSession] is likewise
/// optional -- without it the player simply has no lock-screen presence.
class PlayerBloc extends Bloc<PlayerEvent, PlayerState> {
  PlayerBloc({
    required AudioController audioController,
    PlaybackSettingsRepository? settingsRepository,
    Stream<String?>? userIdChanges,
    MediaSession? mediaSession,
    PlaybackAudioSession? audioSession,
    Random? random,
    // ignore_for_file: prefer_initializing_formals -- keeps public param names.
  }) : _audioController = audioController,
       _settingsRepository = settingsRepository,
       _mediaSession = mediaSession ?? const NoopMediaSession(),
       _audioSession = audioSession ?? const NoopPlaybackAudioSession(),
       _random = random ?? Random(),
       super(const PlayerState()) {
    on<PlayerTrackStarted>(_onTrackStarted);
    on<PlayerPlayPauseToggled>(_onPlayPauseToggled);
    on<PlayerResumeRequested>((_, _) => _resume());
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

    // Losing the speaker to a call, Siri or a nav prompt is not a user gesture,
    // so it gets its own events -- the bloc has to remember whether *it* was the
    // one that stopped playback before it may resume anything.
    _interruptionSub = _audioSession.interruptions.listen((event) {
      add(switch (event) {
        AudioInterruptionBegan(:final duck) => PlayerInterruptionBegan(duck: duck),
        AudioInterruptionEnded(:final shouldResume) => PlayerInterruptionEnded(
          shouldResume: shouldResume,
        ),
        AudioOutputDisconnected() => const PlayerOutputDisconnected(),
      });
    });

    // Volume is stored per account, so the player has to know who is signed in.
    // The stream replays the current user on subscribe, so a restored session
    // applies its saved level at boot without any extra call.
    _userSub = userIdChanges?.listen((userId) => add(PlayerUserChanged(userId)));

    // The OS is just another remote control: its buttons become ordinary events,
    // so a lock-screen tap and an in-app tap go down exactly the same path.
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

  /// The preference sliders fire on every drag frame; this collapses a whole
  /// gesture into a single write (the same debounce idea as SearchCubit).
  static const _settingsSaveDelay = Duration(milliseconds: 400);

  /// How far ahead of the fade window the next track starts buffering. Long
  /// enough for a slow mobile load to finish first, short enough that a second
  /// network stream is only ever open near the end of a track.
  static const _preloadLead = Duration(seconds: 8);

  final AudioController _audioController;
  final PlaybackSettingsRepository? _settingsRepository;
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

  /// How far down ducking takes the volume. Quiet enough that a navigation
  /// prompt is clearly audible over the music, loud enough that the music has
  /// obviously not stopped.
  static const double _duckFactor = 0.3;

  /// True only when the *interruption* is what paused us. Without this the OS
  /// telling us "you can resume now" would start playing music the user had
  /// deliberately paused before the call came in.
  bool _pausedByInterruption = false;

  /// True while volume is being held down for a transient interruption. The
  /// user's own volume ([PlayerState.volume]) is never touched, so nothing gets
  /// persisted and the slider does not jump.
  bool _duckedByInterruption = false;

  /// [NowPlaying.signature] of the last snapshot handed to the OS, so a position
  /// tick four times a second does not become four platform-channel round trips.
  String? _publishedSignature;

  /// The account whose volume is loaded, or null when signed out.
  String? _userId;

  /// True from the moment a crossfade is requested until the incoming track has
  /// loaded -- the window in which state has already advanced but the outgoing
  /// track is still sounding.
  bool _isCrossfading = false;

  Timer? _settingsSaveTimer;

  /// Not-yet-written preference saves, keyed by setting so one slider's pending
  /// write never cancels another's. Each closure captures the account it belongs
  /// to, so a mid-gesture account switch still persists to the right one.
  final Map<String, Future<void> Function()> _pendingSaves = {};

  /// Mirrors state onto the OS media session. Hooked into [onChange] rather than
  /// called from each handler, so no handler can forget it: every state change
  /// the bloc makes passes through here on its way out.
  @override
  void onChange(Change<PlayerState> change) {
    super.onChange(change);
    _publishNowPlaying(change);
  }

  void _publishNowPlaying(Change<PlayerState> change) {
    final next = change.nextState;
    final track = next.currentTrack;
    if (track == null) {
      // Nothing queued: the notification/lock screen must not linger on a dead
      // session. Guarded so repeated empty states don't re-clear.
      if (_publishedSignature == null) return;
      _publishedSignature = null;
      unawaited(_mediaSession.clear().catchError((_) {}));
      return;
    }

    final nowPlaying = NowPlaying.from(next, track);
    // A normal tick moves position by exactly one tick. Anything larger -- or
    // backwards -- is a seek or a track change, and the OS has to hear about it
    // or its extrapolated scrubber drifts away from the one in the app.
    final jumped = (next.position - change.currentState.position).abs() > _tick * 2;
    if (nowPlaying.signature == _publishedSignature && !jumped) return;
    _publishedSignature = nowPlaying.signature;
    unawaited(_mediaSession.update(nowPlaying).catchError((_) {}));
  }

  Future<void> _onTrackStarted(PlayerTrackStarted event, Emitter<PlayerState> emit) async {
    await _startQueue(event.queue, event.startIndex, emit);
  }

  void _onPlayPauseToggled(PlayerPlayPauseToggled event, Emitter<PlayerState> emit) {
    if (state.isPlaying) {
      _pause();
    } else {
      _resume();
    }
  }

  // Fire-and-forget: play()/pause() are not awaited. just_audio's play() future
  // completes when the track ENDS, so awaiting it would block the handler for
  // the whole track -- which on web interleaves badly with the
  // position/buffering event stream. play() resumes from the paused position on
  // its own. isPlaying is not set here either: it follows the engine's
  // playingStream, so the UI and the lock screen only ever show what is real.

  // Both clear _pausedByInterruption: reaching either of these means somebody
  // made a deliberate transport decision, which supersedes anything the OS
  // interrupted. _onInterruptionBegan re-arms the flag straight after calling
  // _pause() for exactly that reason.

  void _resume() {
    _pausedByInterruption = false;
    if (!state.hasTrack) return;
    // Take the audio device back before sounding anything -- resuming after an
    // interruption means somebody else currently owns it.
    unawaited(_claimSessionThen(_audioController.play));
  }

  /// Claims the audio session, then does [play]. Ordered, because playing into a
  /// session we do not own is how you end up mixed under another app instead of
  /// interrupting it.
  Future<void> _claimSessionThen(Future<void> Function() play) async {
    await _audioSession.activate().catchError((_) {});
    // Not awaited by callers: just_audio's play() completes at the track's END.
    await play().catchError((_) {});
  }

  void _pause() {
    _pausedByInterruption = false;
    if (!state.hasTrack) return;
    unawaited(_audioController.pause().catchError((_) {}));
  }

  /// Makes the engine agree with a state that says "not playing", for the paths
  /// where playback ends without anybody pressing pause: a queue running out, or
  /// a load that failed.
  ///
  /// The engine never stops itself. `playing` is play *intent* (see
  /// [AudioController.playingStream]): it stays true when a source reaches its
  /// end, leaving the engine parked at the end of a track it still considers
  /// current. Emitting `isPlaying: false` over that lies twice over:
  ///
  ///  * play() is documented to return immediately while `playing` is already
  ///    true, so the play button does nothing at all; and
  ///  * because nothing actually changed, playingStream stays silent -- so the
  ///    next source that *does* load starts sounding with isPlaying still false,
  ///    which shows up as a transport frozen at 0:00 over audible music.
  ///
  /// Unlike [_pause] this is awaited, since callers emit straight afterwards and
  /// the engine's own `playing: false` has to be on its way first.
  Future<void> _haltPlayback() => _audioController.pause().catchError((_) {});

  void _onInterruptionBegan(PlayerInterruptionBegan event, Emitter<PlayerState> emit) {
    if (!state.hasTrack) return;

    if (event.duck) {
      // Keep playing, just get out of the way. Applied straight to the engine so
      // state.volume -- the user's setting, which is persisted per account --
      // stays exactly where they left it.
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
    // _pause() clears _pausedByInterruption, which is the point: unplugging
    // headphones must never lead to music resuming later out of the speaker.
    _pause();
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
    // Hand the audio device back: we are done with it, so anything we
    // interrupted (a podcast in another app) is free to carry on.
    await _audioSession.deactivate().catchError((_) {});
    emit(_clearedState());
  }

  Future<void> _onPositionTicked(PlayerPositionTicked event, Emitter<PlayerState> emit) async {
    // Don't advance while a (new) track is still buffering -- on auto-advance
    // just_audio keeps `playing` true across the track boundary, so without
    // this guard the scrubber would move before the next track's audio has
    // actually started.
    if (!state.isPlaying || state.isLoading) return;
    final next = state.position + _tick;
    // Cap at the (known) duration so the thumb never runs past the end.
    final capped = state.duration > Duration.zero && next > state.duration ? state.duration : next;
    emit(state.copyWith(position: capped));

    // The ticker doubles as the crossfade trigger: it is the one place that
    // knows, every 250ms, how close the current track is to its end.
    _maybePreloadNext(capped);
    if (!_shouldStartCrossfade(capped)) return;
    final upcoming = _nextIndexOnCompletion();
    if (upcoming == null) return;
    await _crossfadeTo(upcoming, emit);
  }

  /// Gets the next track buffered *before* the fade window opens.
  ///
  /// Without this the load lands inside the fade: the outgoing track keeps
  /// playing alone until it finishes, so a 3s crossfade over a 2s load gives
  /// only 1s of overlap, and a load slower than the fade gives none at all --
  /// which is indistinguishable from crossfade not working. The conditions
  /// mirror [_shouldStartCrossfade], so we only ever pre-buffer a track that is
  /// actually going to be faded in.
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
    // Called on every tick inside the window -- the controller dedupes by url,
    // so this stays a no-op after the first one lands (or fails).
    unawaited(_audioController.preload(state.queue[upcoming].audioUrl).catchError((_) {}));
  }

  /// Whether we are inside the window where the next track should start fading
  /// in underneath this one.
  bool _shouldStartCrossfade(Duration position) {
    if (_isCrossfading) return false; // one already in flight
    final fade = state.crossfadeDuration;
    if (fade <= Duration.zero) return false;
    if (!_audioController.supportsCrossfade) return false;

    final duration = state.duration;
    // A track that isn't comfortably longer than the fade gets a plain cut.
    // This is also what stops a runaway: without it, a freshly-started short
    // track would already be inside its own fade window and skip on every tick.
    if (duration <= fade * 2) return false;

    // Having to be at least `fade` in gives every crossfade a cooldown, since
    // starting one resets position to zero.
    if (position < fade) return false;

    return position >= duration - fade;
  }

  /// Where playback goes when the current track finishes, honouring repeat, or
  /// null if it should stop. Shared by natural completion and the crossfade
  /// trigger so the two can never disagree.
  int? _nextIndexOnCompletion() {
    final isLast = state.currentIndex >= state.queue.length - 1;
    return switch (state.repeatMode) {
      PlayerRepeatMode.one => state.currentIndex,
      PlayerRepeatMode.all => isLast ? 0 : state.currentIndex + 1,
      PlayerRepeatMode.off => isLast ? null : state.currentIndex + 1,
    };
  }

  /// Moves to [index] by overlapping it with the outgoing track. Deliberately
  /// does NOT set isLoading: the point of a crossfade is that nothing visibly
  /// stalls, and the new audio is already audible while it loads.
  Future<void> _crossfadeTo(int index, Emitter<PlayerState> emit) async {
    final track = state.queue[index];
    emit(state.copyWith(currentIndex: index, position: Duration.zero, duration: track.duration));
    // Loading the incoming track is a network round-trip; until it lands we have
    // already advanced, so nothing else may advance again (see _onCompleted).
    _isCrossfading = true;
    try {
      final duration = await _audioController.crossfadeTo(
        track.audioUrl,
        fade: state.crossfadeDuration,
      );
      // Only trust this for the track we actually asked for. Pressing Next
      // during the load supersedes us, and applying a stale duration would put
      // the fade window somewhere unreachable -- which looks exactly like
      // crossfade having silently stopped working.
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
    // A crossfade has already advanced us; the outgoing track reaching its end
    // is old news. Without this, the track we just faded into would be skipped.
    if (_isCrossfading) return;

    final upcoming = _nextIndexOnCompletion();
    if (upcoming == null) {
      await _haltPlayback();
      // Rewind so the engine is where the state below says it is: at the start,
      // ready to play the track again. Strictly AFTER the pause -- seeking while
      // the engine still holds play intent just carries on playing from the new
      // position.
      await _audioController.seek(Duration.zero).catchError((_) {});
      emit(state.copyWith(isPlaying: false, position: Duration.zero));
      return;
    }
    // Reload even when repeating one track rather than seek(0)+play(): every
    // track-change path here goes through _playCurrent, and a fresh load is the
    // one behaviour we've verified on all four platforms.
    await _goTo(upcoming, emit);
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

    // Any half-dragged preference still belongs to the OUTGOING account -- write
    // it before switching, since each pending save captured that account's id.
    await _flushSaves();
    _userId = event.userId;

    final userId = event.userId;
    final repository = _settingsRepository;
    // Signed out: forget this account's preferences rather than leaking them to
    // whoever signs in next.
    final volume = userId == null
        ? _defaultVolume
        : await repository?.fetchVolume(userId) ?? _defaultVolume;
    final crossfade = userId == null
        ? Duration.zero
        : await repository?.fetchCrossfadeDuration(userId) ?? Duration.zero;

    emit(state.copyWith(volume: volume, crossfadeDuration: crossfade));
    await _audioController.setVolume(volume).catchError((_) {});
  }

  void _scheduleSave(String key, Future<void> Function() save) {
    _pendingSaves[key] = save; // latest write for this setting wins
    _settingsSaveTimer?.cancel();
    _settingsSaveTimer = Timer(_settingsSaveDelay, () => unawaited(_flushSaves()));
  }

  /// Writes any pending preferences immediately. Called when the debounce
  /// elapses, on account switch, and on close -- so a save is never lost.
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

    emit(
      state.copyWith(
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
    crossfadeDuration: state.crossfadeDuration,
  );

  Future<void> _playCurrent(Emitter<PlayerState> emit) async {
    final track = state.currentTrack;
    if (track == null) return;
    // Claim the audio device before loading, so we take it from whatever else is
    // playing rather than quietly mixing underneath it.
    await _audioSession.activate().catchError((_) {});
    try {
      // setUrl returns the duration when the engine knows it at load time.
      final duration = await _audioController.setUrl(track.audioUrl);
      // A newer track change overtook this load: its own _playCurrent owns the
      // player now, so applying our duration (or starting playback below) would
      // fight it.
      if (state.currentTrack?.id != track.id) return;
      // Only override the seeded duration with a real engine value (iOS
      // returns 0 here).
      if (duration != null && duration > Duration.zero) emit(state.copyWith(duration: duration));
      // Re-assert volume: on web the source switch above tears down and rebuilds
      // the underlying player (see JustAudioController.setUrl), which would
      // otherwise silently reset it to full.
      if (state.volume != 1) await _audioController.setVolume(state.volume).catchError((_) {});
    } catch (_) {
      // The load failed, so nothing is going to sound -- but the engine may
      // still be holding play intent from the previous track. See _haltPlayback.
      await _haltPlayback();
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
    // Don't lose a preference change made within the debounce window.
    await _flushSaves();
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
