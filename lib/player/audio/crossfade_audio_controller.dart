import 'dart:async';

import 'audio_controller.dart';

/// An [AudioController] that overlaps two underlying players so one track can
/// fade out while the next fades in.
///
/// It is a *decorator*: it implements the same single-source interface it wraps,
/// so [PlayerBloc] keeps talking to "the player" and never learns there are two.
/// Only the mechanism lives here (which player is sounding, the volume ramp);
/// the policy of *when* to start a fade stays with the bloc, which is the only
/// thing that knows the queue.
///
/// Exactly one of the two players is "active" at a time -- the one whose streams
/// are forwarded and which every ordinary call ([play], [seek], ...) operates
/// on. [crossfadeTo] loads the next track on the standby player, hands the
/// active role over to it immediately, and then ramps the volumes past each
/// other in the background.
class CrossfadeAudioController implements AudioController {
  CrossfadeAudioController({
    required AudioController Function() createPlayer,
    Duration rampStep = const Duration(milliseconds: 50),
        // ignore_for_file: prefer_initializing_formals -- keeps public param names.
  })  : _players = [createPlayer(), createPlayer()],
        _rampStep = rampStep {
    _bindActive();
  }

  final List<AudioController> _players;

  /// How often the fade adjusts volumes. Small enough to be inaudible as steps,
  /// large enough not to spam the platform channel.
  final Duration _rampStep;

  int _activeIndex = 0;

  AudioController get _active => _players[_activeIndex];
  AudioController get _standby => _players[1 - _activeIndex];

  /// The volume the user asked for. Every ramp is scaled by it, so a fade never
  /// plays louder than requested and both players settle back to it.
  double _volume = 1;

  Timer? _rampTimer;
  bool _isCrossfading = false;

  /// The player whose track is being replaced, from the moment a crossfade
  /// starts until it is retired. Its natural completion is never reported: the
  /// caller has already moved on, and loading the incoming track can take
  /// seconds, so the outgoing track may well end before the handover.
  AudioController? _fadingOut;

  /// Identifies the current crossfade attempt. Anything that supersedes a fade
  /// (an explicit track change, stop, another fade) bumps it, so a load still in
  /// flight can tell it has been overtaken and must not hijack playback when it
  /// lands.
  int _fadeAttempt = 0;

  // Ramp progress, held as fields rather than closure locals so a fade can be
  // frozen by [pause] and picked up again by [play] instead of being thrown away.
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
    // An explicit track change (Next, tapping a row) supersedes any fade in
    // flight -- the user asked for this track now.
    await _abortCrossfade();
    return _active.setUrl(url);
  }

  @override
  Future<void> preload(String url) async {
    // The standby player is the incoming side of a fade in flight -- loading
    // something else into it now would cut the fade off.
    if (_isCrossfading) return;
    if (_preloadedUrl == url) return; // already loaded, or already tried
    _discardPreload();
    _preloadedUrl = url;
    final target = _standby;
    try {
      // Silent, and deliberately never played: it just sits buffered.
      await target.setVolume(0);
      final duration = await target.setUrl(url);
      // A fade or an explicit track change may have claimed the standby while
      // this was loading, in which case what we loaded is no longer valid.
      if (_preloadedUrl != url) return;
      _preloadedDuration = duration;
      _preloadIsReady = true;
    } catch (_) {
      // Leave _preloadedUrl set so this is not retried on every tick;
      // crossfadeTo just loads the track itself, exactly as it used to.
    }
  }

  @override
  Future<Duration?> crossfadeTo(String url, {required Duration fade}) async {
    if (fade <= Duration.zero) return setUrl(url);

    // Collapse a fade that is still running rather than stacking ramps.
    await _abortCrossfade();

    final outgoing = _active;
    final incoming = _standby;

    // Claim the fade BEFORE loading. The load below is a network round-trip that
    // can easily outlast the rest of the outgoing track, and from here on that
    // track is history: its completion must not be reported as "time for the
    // next one" (the caller has already advanced).
    final attempt = ++_fadeAttempt;
    _isCrossfading = true;
    _fadingOut = outgoing;

    // Already buffered by [preload]? Then there is nothing to wait for and the
    // ramp below starts immediately, so the fade lasts its full length.
    final wasPreloaded = _preloadIsReady && _preloadedUrl == url;
    final preloadedDuration = _preloadedDuration;
    _discardPreload(); // consumed either way: this player is no longer standby

    Duration? duration;
    try {
      if (wasPreloaded) {
        duration = preloadedDuration;
      } else {
        // Silent first, so nothing is audible before the ramp begins.
        await incoming.setVolume(0);
        duration = await incoming.setUrl(url);
      }
      // NOT awaited: just_audio's play() future completes when the track
      // *ends*, not when it starts. Awaiting it here would park this method for
      // the length of the whole incoming track -- so the handover and the volume
      // ramp below would never run, leaving the new track stuck at volume 0.
      //
      // Skipped entirely while paused: the fade is set up but stays silent until
      // play() resumes it.
      if (!_isPaused) unawaited(incoming.play().catchError((_) {}));
    } catch (_) {
      // Couldn't get the next track going on the spare player: fall back to a
      // plain cut on the one already sounding.
      await incoming.stop().catchError((_) {});
      await incoming.setVolume(_volume).catchError((_) {});
      if (attempt == _fadeAttempt) {
        _isCrossfading = false;
        _fadingOut = null;
      }
      return _active.setUrl(url);
    }

    // Something overtook us while the track was loading (Next, pause, stop, or
    // another fade). Whatever is playing now wins -- retire what we loaded.
    if (attempt != _fadeAttempt) {
      await incoming.stop().catchError((_) {});
      await incoming.setVolume(_volume).catchError((_) {});
      return duration;
    }

    // Hand over: from here on, "the current source" is the incoming track, and
    // it is its duration/buffering/completion the caller should see.
    _activeIndex = 1 - _activeIndex;
    _bindActive();

    _prepareRamp(outgoing: outgoing, fade: fade);

    return duration;
  }

  /// Sets up a fade that walks both players' volumes past each other over
  /// [fade]. It only starts ticking if we are not paused.
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

  /// One step of the fade. The incoming side is simply the active player, since
  /// the handover happens before the ramp begins.
  Future<void> _advanceRamp() async {
    final outgoing = _rampOutgoing;
    if (outgoing == null) return;

    _rampStepIndex++;
    final progress = (_rampStepIndex / _rampSteps).clamp(0.0, 1.0);
    // Scaled by _volume (read live), so changing volume mid-fade behaves.
    await outgoing.setVolume(_volume * (1 - progress)).catchError((_) {});
    await _active.setVolume(_volume * progress).catchError((_) {});
    if (progress < 1) return;

    _rampTimer?.cancel();
    _rampTimer = null;
    _rampOutgoing = null;
    if (_fadingOut == outgoing) _fadingOut = null;
    // Release the finished track and leave that player ready for reuse.
    await outgoing.stop().catchError((_) {});
    await outgoing.setVolume(_volume).catchError((_) {});
    // Cleared LAST, on purpose: _isCrossfading is what keeps preload() off the
    // standby player. Clearing it before the stop() above would let a preload
    // begin and then have its source torn down by that stop -- leaving a track
    // marked "ready to fade in" that is actually silent.
    _isCrossfading = false;
  }

  /// Ends any in-flight fade at once, silencing the outgoing track and putting
  /// both players back at full requested volume.
  Future<void> _abortCrossfade() async {
    _rampTimer?.cancel();
    _rampTimer = null;
    if (!_isCrossfading) return;
    // The stop() below releases whatever the standby holds, including anything
    // preloaded into it.
    _discardPreload();
    _isCrossfading = false;
    _fadingOut = null;
    _rampOutgoing = null;
    // Supersede any load still in flight so it cannot hand over behind us.
    _fadeAttempt++;
    // The player to silence is whichever one is not active: during the load that
    // is the incoming track we were bringing up, and after the handover it is
    // the outgoing one still fading.
    await _standby.stop().catchError((_) {});
    await _standby.setVolume(_volume).catchError((_) {});
    await _active.setVolume(_volume).catchError((_) {});
  }

  @override
  Future<void> play() {
    _isPaused = false;
    // Resume a frozen fade rather than dropping the outgoing track: pausing
    // mid-crossfade and pressing play should carry on where it left off.
    if (_isCrossfading) {
      final outgoing = _rampOutgoing;
      if (outgoing != null) {
        // Fire-and-forget for the same reason as below: play() resolves at the
        // track's end.
        unawaited(outgoing.play().catchError((_) {}));
        _startRampTimer();
      }
    }
    // Returned unawaited by callers -- this future completes when the track ends.
    return _active.play();
  }

  @override
  Future<void> pause() async {
    _isPaused = true;
    // FREEZE the fade, don't destroy it: both tracks hold their current levels
    // and resume together. (Aborting here would silence the outgoing track for
    // good, so pausing mid-crossfade would lose it.)
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
