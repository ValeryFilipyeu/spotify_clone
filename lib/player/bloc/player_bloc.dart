import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../audio/audio_controller.dart';
import 'player_event.dart';
import 'player_state.dart';

/// App-wide, one instance for the whole app lifetime (like AuthBloc). Owns the
/// playback queue and mirrors the [AudioController]'s streams into state so the
/// mini-player and full player can both react. It never navigates.
class PlayerBloc extends Bloc<PlayerEvent, PlayerState> {
  PlayerBloc({required AudioController audioController})
      // ignore: prefer_initializing_formals -- keeps the public param name.
      : _audioController = audioController,
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

    // NOTE: we deliberately do NOT drive `position` from
    // audioController.positionStream. just_audio's position getter clamps to
    // the engine-reported duration while playing, and on iOS that duration is
    // 0 -- so its position is pinned to 0:00 during playback (it only reveals
    // the true position when paused). Instead we run our own wall-clock ticker
    // below, which is smooth and consistent on every platform.
    _durationSub = _audioController.durationStream.listen((d) {
      // Ignore null and 0 -- iOS reports duration as Duration.zero, which
      // would clobber the seeded track duration.
      if (d != null && d > Duration.zero) add(PlayerDurationChanged(d));
    });
    _playingSub = _audioController.playingStream.listen((playing) => add(PlayerPlayingChanged(playing)));
    _bufferingSub = _audioController.bufferingStream.listen((b) => add(PlayerBufferingChanged(b)));
    _completedSub = _audioController.completedStream.listen((_) => add(const PlayerCompleted()));
  }

  static const _tick = Duration(milliseconds: 250);

  final AudioController _audioController;
  late final StreamSubscription<Duration?> _durationSub;
  late final StreamSubscription<bool> _playingSub;
  late final StreamSubscription<bool> _bufferingSub;
  late final StreamSubscription<void> _completedSub;
  Timer? _ticker;

  Future<void> _onTrackStarted(PlayerTrackStarted event, Emitter<PlayerState> emit) async {
    emit(state.copyWith(
      queue: event.queue,
      currentIndex: event.startIndex,
      isLoading: true,
      position: Duration.zero,
      // Seed from the track's known duration so the scrubber has a scale
      // immediately. On iOS the audio engine reports duration as 0 (never the
      // real value), so this seed is what the timeline relies on there; on
      // Android/web the engine's real duration overrides it (see below).
      duration: event.queue[event.startIndex].duration,
    ));
    await _playCurrent(emit);
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
    if (!state.hasNext) return;
    final next = state.currentIndex + 1;
    emit(state.copyWith(currentIndex: next, isLoading: true, position: Duration.zero, duration: state.queue[next].duration));
    await _playCurrent(emit);
  }

  Future<void> _onPreviousRequested(PlayerPreviousRequested event, Emitter<PlayerState> emit) async {
    if (!state.hasPrevious) return;
    final prev = state.currentIndex - 1;
    emit(state.copyWith(currentIndex: prev, isLoading: true, position: Duration.zero, duration: state.queue[prev].duration));
    await _playCurrent(emit);
  }

  Future<void> _onSeekRequested(PlayerSeekRequested event, Emitter<PlayerState> emit) async {
    await _audioController.seek(event.position);
    emit(state.copyWith(position: event.position));
  }

  Future<void> _onStopped(PlayerStopped event, Emitter<PlayerState> emit) async {
    await _audioController.stop();
    emit(const PlayerState());
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
    // Drive the position ticker off play/pause. (We can't use just_audio's
    // position stream -- see the note in the constructor.)
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
    if (state.hasNext) {
      final next = state.currentIndex + 1;
      emit(state.copyWith(currentIndex: next, isLoading: true, position: Duration.zero, duration: state.queue[next].duration));
      await _playCurrent(emit);
    } else {
      emit(state.copyWith(isPlaying: false, position: Duration.zero));
    }
  }

  Future<void> _playCurrent(Emitter<PlayerState> emit) async {
    final track = state.currentTrack;
    if (track == null) return;
    try {
      // setUrl returns the duration when the engine knows it at load time.
      final duration = await _audioController.setUrl(track.audioUrl);
      // Only override the seeded duration with a real engine value (iOS
      // returns 0 here).
      if (duration != null && duration > Duration.zero) emit(state.copyWith(duration: duration));
    } catch (_) {
      emit(state.copyWith(isLoading: false, isPlaying: false));
      return;
    }
    // Fire-and-forget (see _onPlayPauseToggled): play() completes on track
    // END, so it must not be awaited here. Completion is handled via
    // completedStream; playing/loading via the playing/buffering streams.
    unawaited(_audioController.play().catchError((_) {}));
  }

  @override
  Future<void> close() {
    _ticker?.cancel();
    _durationSub.cancel();
    _playingSub.cancel();
    _bufferingSub.cancel();
    _completedSub.cancel();
    _audioController.dispose();
    return super.close();
  }
}
