import 'dart:async';

import 'audio_controller.dart';

/// Overlaps two players so one track can fade out while the next fades in,
/// behind the same single-source interface -- [PlayerBloc] never learns there
/// are two. Only the mechanism lives here; *when* to fade stays with the bloc,
/// which is the only thing that knows the queue.
///
/// One player is "active" at a time: its streams are forwarded and every
/// ordinary call operates on it. [crossfadeTo] loads onto the standby, hands the
/// active role over immediately, then ramps the volumes past each other.
class CrossfadeAudioController implements AudioController {
  CrossfadeAudioController({
    required AudioController Function() createPlayer,
    Duration rampStep = const Duration(milliseconds: 50),
    // ignore_for_file: prefer_initializing_formals -- keeps public param names.
  }) : _players = [createPlayer(), createPlayer()],
       _rampStep = rampStep {
    _bindActive();
  }

  final List<AudioController> _players;

  /// Inaudible as steps, but not so fine it spams the platform channel.
  final Duration _rampStep;

  int _activeIndex = 0;

  AudioController get _active => _players[_activeIndex];
  AudioController get _standby => _players[1 - _activeIndex];

  /// The volume the user asked for. Ramps are scaled by it, so a fade never
  /// plays louder than requested.
  double _volume = 1;

  Timer? _rampTimer;
  bool _isCrossfading = false;

  /// The player being replaced. Its completion is never reported -- the caller
  /// has already moved on, and a slow load can outlast the outgoing track.
  AudioController? _fadingOut;

  /// Bumped by anything that supersedes a fade, so an in-flight load can tell it
  /// was overtaken and must not hijack playback when it lands.
  int _fadeAttempt = 0;

  // Fields, not closure locals, so [pause] can freeze a fade and [play] resume
  // it instead of throwing it away.
  AudioController? _rampOutgoing;
  int _rampStepIndex = 0;
  int _rampSteps = 1;

  /// Whether the user has paused. A fade that is mid-flight (or a track still
  /// loading for one) must not start sounding while paused.
  bool _isPaused = false;

  // The track sitting ready (and silent) on the standby player, so a fade can
  // start the instant it is asked for. [_preloadedUrl] is set as soon as a
  // preload is *attempted* -- it doubles as "already tried this one", which
  // keeps a failing url from being re-fetched on every position tick --
  // while [_preloadIsReady] says whether it actually landed.
  String? _preloadedUrl;
  bool _preloadIsReady = false;
  Duration? _preloadedDuration;

  void _discardPreload() {
    _preloadedUrl = null;
    _preloadIsReady = false;
    _preloadedDuration = null;
  }

  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration?>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _completed = StreamController<void>.broadcast();

  final List<StreamSubscription<dynamic>> _activeSubs = [];

  /// Bumped on every rebind. Forwarding closures capture the generation they
  /// were created with and go quiet once it is stale -- so an event already
  /// in flight from the outgoing player (its natural completion, most
  /// importantly) can never reach the bloc after the handover.
  int _generation = 0;

  void _bindActive() {
    for (final sub in _activeSubs) {
      sub.cancel();
    }
    _activeSubs.clear();

    final generation = ++_generation;
    bool isCurrent() => generation == _generation;
    final player = _active;

    _activeSubs.addAll([
      player.positionStream.listen((v) => isCurrent() ? _position.add(v) : null),
      player.durationStream.listen((v) => isCurrent() ? _duration.add(v) : null),
      player.playingStream.listen((v) => isCurrent() ? _playing.add(v) : null),
      player.bufferingStream.listen((v) => isCurrent() ? _buffering.add(v) : null),
      // Suppressed for the track being faded out even while it is still the
      // active player -- which it is for as long as the incoming track takes to
      // load. Keyed on the player itself rather than a flag, so a very short
      // incoming track's own completion still gets through.
      player.completedStream.listen((_) {
        if (isCurrent() && player != _fadingOut) _completed.add(null);
      }),
    ]);
  }

  @override
  Stream<Duration> get positionStream => _position.stream;

  @override
  Stream<Duration?> get durationStream => _duration.stream;

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Stream<bool> get bufferingStream => _buffering.stream;

  @override
  Stream<void> get completedStream => _completed.stream;

  @override
  bool get supportsCrossfade => true;

  @override
  Future<Duration?> setUrl(String url) async {
    // An explicit track change supersedes any fade in flight.
    await _abortCrossfade();
    return _active.setUrl(url);
  }

  @override
  Future<void> preload(String url) async {
    // Standby is the incoming side of a live fade; loading over it cuts it off.
    if (_isCrossfading) return;
    if (_preloadedUrl == url) return; // already loaded, or already tried
    _discardPreload();
    _preloadedUrl = url;
    final target = _standby;
    try {
      await target.setVolume(0);
      final duration = await target.setUrl(url);
      // Something claimed the standby while this was loading.
      if (_preloadedUrl != url) return;
      _preloadedDuration = duration;
      _preloadIsReady = true;
    } catch (_) {
      // _preloadedUrl stays set so this is not retried every tick; crossfadeTo
      // loads the track itself instead.
    }
  }

  @override
  Future<Duration?> crossfadeTo(String url, {required Duration fade}) async {
    if (fade <= Duration.zero) return setUrl(url);

    await _abortCrossfade();

    final outgoing = _active;
    final incoming = _standby;

    // Before loading, because the load can outlast the outgoing track -- whose
    // completion must not be reported as "time for the next one".
    final attempt = ++_fadeAttempt;
    _isCrossfading = true;
    _fadingOut = outgoing;

    // Buffered by [preload] means the ramp starts now and gets its full length.
    final wasPreloaded = _preloadIsReady && _preloadedUrl == url;
    final preloadedDuration = _preloadedDuration;
    _discardPreload(); // consumed either way: this player is no longer standby

    Duration? duration;
    try {
      if (wasPreloaded) {
        duration = preloadedDuration;
      } else {
        await incoming.setVolume(0);
        duration = await incoming.setUrl(url);
      }
      // Not awaited: play() resolves at the track's END, so awaiting would park
      // the handover and leave the new track stuck at volume 0. Skipped while
      // paused -- the fade is set up but stays silent until play() resumes it.
      if (!_isPaused) unawaited(incoming.play().catchError((_) {}));
    } catch (_) {
      // The spare player would not start: fall back to a plain cut.
      await incoming.stop().catchError((_) {});
      await incoming.setVolume(_volume).catchError((_) {});
      if (attempt == _fadeAttempt) {
        _isCrossfading = false;
        _fadingOut = null;
      }
      return _active.setUrl(url);
    }

    // Something overtook us mid-load; whatever plays now wins.
    if (attempt != _fadeAttempt) {
      await incoming.stop().catchError((_) {});
      await incoming.setVolume(_volume).catchError((_) {});
      return duration;
    }

    // From here on the incoming track is the one the caller sees.
    _activeIndex = 1 - _activeIndex;
    _bindActive();

    _prepareRamp(outgoing: outgoing, fade: fade);

    return duration;
  }

  /// Walks both players' volumes past each other over [fade]. Only ticks if not
  /// paused.
  void _prepareRamp({required AudioController outgoing, required Duration fade}) {
    _rampOutgoing = outgoing;
    _rampSteps = (fade.inMilliseconds / _rampStep.inMilliseconds).ceil().clamp(1, 100000);
    _rampStepIndex = 0;
    if (!_isPaused) _startRampTimer();
  }

  void _startRampTimer() {
    _rampTimer?.cancel();
    _rampTimer = Timer.periodic(_rampStep, (_) => unawaited(_advanceRamp()));
  }

  /// One step. The incoming side is just the active player: handover precedes
  /// the ramp.
  Future<void> _advanceRamp() async {
    final outgoing = _rampOutgoing;
    if (outgoing == null) return;

    _rampStepIndex++;
    final progress = (_rampStepIndex / _rampSteps).clamp(0.0, 1.0);
    // Read live, so changing volume mid-fade behaves.
    await outgoing.setVolume(_volume * (1 - progress)).catchError((_) {});
    await _active.setVolume(_volume * progress).catchError((_) {});
    if (progress < 1) return;

    _rampTimer?.cancel();
    _rampTimer = null;
    _rampOutgoing = null;
    if (_fadingOut == outgoing) _fadingOut = null;
    await outgoing.stop().catchError((_) {});
    await outgoing.setVolume(_volume).catchError((_) {});
    // Last, because it is what keeps preload() off the standby: clearing it
    // before the stop() would let a preload start and then be torn down by it.
    _isCrossfading = false;
  }

  /// Ends any fade at once, silencing the outgoing track and restoring volumes.
  Future<void> _abortCrossfade() async {
    _rampTimer?.cancel();
    _rampTimer = null;
    if (!_isCrossfading) return;
    _discardPreload();
    _isCrossfading = false;
    _fadingOut = null;
    _rampOutgoing = null;
    // Supersede any in-flight load so it cannot hand over behind us.
    _fadeAttempt++;
    // Whichever is not active: the incoming track during the load, the outgoing
    // one after the handover.
    await _standby.stop().catchError((_) {});
    await _standby.setVolume(_volume).catchError((_) {});
    await _active.setVolume(_volume).catchError((_) {});
  }

  @override
  Future<void> play() {
    _isPaused = false;
    // Resume a frozen fade rather than dropping the outgoing track.
    if (_isCrossfading) {
      final outgoing = _rampOutgoing;
      if (outgoing != null) {
        unawaited(outgoing.play().catchError((_) {}));
        _startRampTimer();
      }
    }
    return _active.play();
  }

  @override
  Future<void> pause() async {
    _isPaused = true;
    // Freeze, don't abort: aborting would silence the outgoing track for good.
    _rampTimer?.cancel();
    _rampTimer = null;
    if (_isCrossfading) {
      await _rampOutgoing?.pause().catchError((_) {});
    }
    await _active.pause();
  }

  @override
  Future<void> seek(Duration position) => _active.seek(position);

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
    // Only the active player: the outgoing one is mid-ramp and the ramp already
    // scales by the new value.
    await _active.setVolume(volume);
  }

  @override
  Future<void> stop() async {
    await _abortCrossfade();
    _discardPreload(); // both players are released below
    for (final player in _players) {
      await player.stop().catchError((_) {});
    }
  }

  @override
  Future<void> dispose() async {
    _rampTimer?.cancel();
    _rampTimer = null;
    for (final sub in _activeSubs) {
      await sub.cancel();
    }
    _activeSubs.clear();
    for (final player in _players) {
      await player.dispose();
    }
    await _position.close();
    await _duration.close();
    await _playing.close();
    await _buffering.close();
    await _completed.close();
  }
}
