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
    on<PlayerPositionChanged>(_onPositionChanged);
    on<PlayerDurationChanged>(_onDurationChanged);
    on<PlayerPlayingChanged>(_onPlayingChanged);
    on<PlayerBufferingChanged>(_onBufferingChanged);
    on<PlayerCompleted>(_onCompleted);

    _positionSub = _audioController.positionStream.listen((p) => add(PlayerPositionChanged(p)));
    _durationSub = _audioController.durationStream.listen((d) {
      if (d != null) add(PlayerDurationChanged(d));
    });
    _playingSub = _audioController.playingStream.listen((playing) => add(PlayerPlayingChanged(playing)));
    _bufferingSub = _audioController.bufferingStream.listen((b) => add(PlayerBufferingChanged(b)));
    _completedSub = _audioController.completedStream.listen((_) => add(const PlayerCompleted()));
  }

  final AudioController _audioController;
  late final StreamSubscription<Duration> _positionSub;
  late final StreamSubscription<Duration?> _durationSub;
  late final StreamSubscription<bool> _playingSub;
  late final StreamSubscription<bool> _bufferingSub;
  late final StreamSubscription<void> _completedSub;

  Future<void> _onTrackStarted(PlayerTrackStarted event, Emitter<PlayerState> emit) async {
    emit(state.copyWith(
      queue: event.queue,
      currentIndex: event.startIndex,
      isLoading: true,
      position: Duration.zero,
      duration: Duration.zero,
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
    emit(state.copyWith(currentIndex: state.currentIndex + 1, isLoading: true, position: Duration.zero, duration: Duration.zero));
    await _playCurrent(emit);
  }

  Future<void> _onPreviousRequested(PlayerPreviousRequested event, Emitter<PlayerState> emit) async {
    if (!state.hasPrevious) return;
    emit(state.copyWith(currentIndex: state.currentIndex - 1, isLoading: true, position: Duration.zero, duration: Duration.zero));
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

  void _onPositionChanged(PlayerPositionChanged event, Emitter<PlayerState> emit) {
    emit(state.copyWith(position: event.position));
  }

  void _onDurationChanged(PlayerDurationChanged event, Emitter<PlayerState> emit) {
    emit(state.copyWith(duration: event.duration));
  }

  void _onPlayingChanged(PlayerPlayingChanged event, Emitter<PlayerState> emit) {
    // isLoading is driven by bufferingStream, NOT by this -- just_audio's
    // `playing` stays true across a track boundary, so it can't tell us when
    // the next track has finished loading.
    emit(state.copyWith(isPlaying: event.isPlaying));
  }

  void _onBufferingChanged(PlayerBufferingChanged event, Emitter<PlayerState> emit) {
    emit(state.copyWith(isLoading: event.isBuffering));
  }

  Future<void> _onCompleted(PlayerCompleted event, Emitter<PlayerState> emit) async {
    if (state.hasNext) {
      emit(state.copyWith(currentIndex: state.currentIndex + 1, isLoading: true, position: Duration.zero, duration: Duration.zero));
      await _playCurrent(emit);
    } else {
      emit(state.copyWith(isPlaying: false, position: Duration.zero));
    }
  }

  Future<void> _playCurrent(Emitter<PlayerState> emit) async {
    final track = state.currentTrack;
    if (track == null) return;
    try {
      // setUrl returns the duration when the engine knows it at load time,
      // which is more reliable than durationStream on web.
      final duration = await _audioController.setUrl(track.audioUrl);
      if (duration != null) emit(state.copyWith(duration: duration));
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
    _positionSub.cancel();
    _durationSub.cancel();
    _playingSub.cancel();
    _bufferingSub.cancel();
    _completedSub.cancel();
    _audioController.dispose();
    return super.close();
  }
}
