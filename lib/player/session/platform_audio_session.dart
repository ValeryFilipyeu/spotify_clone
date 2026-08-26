import 'dart:async';

import 'package:audio_session/audio_session.dart' as platform;

import 'playback_audio_session.dart';

/// The real OS audio session, and the only file that imports audio_session.
class PlatformAudioSession implements PlaybackAudioSession {
  PlatformAudioSession._(this._session, this.interruptions);

  static Future<PlatformAudioSession> create() async {
    final session = await platform.AudioSession.instance;

    // Nothing else in the stack does this (verified in both plugins' native
    // code), and without it iOS leaves us on a category that mixes with other
    // apps and delivers no interruptions. music() is the documented preset:
    // .playback on iOS, media attributes and full focus gain on Android.
    await session.configure(const platform.AudioSessionConfiguration.music());

    final controller = StreamController<AudioInterruption>.broadcast();
    controller.onListen = () {
      final subscriptions = <StreamSubscription<dynamic>>[
        session.interruptionEventStream.listen((event) => controller.add(_translate(event))),
        // Carries nothing but the fact that it happened.
        session.becomingNoisyEventStream.listen((_) {
          controller.add(const AudioOutputDisconnected());
        }),
      ];
      controller.onCancel = () async {
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      };
    };

    return PlatformAudioSession._(session, controller.stream);
  }

  final platform.AudioSession _session;

  @override
  final Stream<AudioInterruption> interruptions;

  // Also the Android audio-focus request, and audio_session reports focus
  // changes only for a request it made -- so without this there are no Android
  // interruptions at all.
  @override
  Future<void> activate() => _session.setActive(true);

  @override
  Future<void> deactivate() => _session.setActive(false);

  static AudioInterruption _translate(platform.AudioInterruptionEvent event) {
    if (event.begin) {
      return AudioInterruptionBegan(duck: event.type == platform.AudioInterruptionType.duck);
    }
    // `pause` is a finished interruption, so resuming is expected. `unknown`
    // means the platform will not vouch for that, and `duck` never stopped us.
    return AudioInterruptionEnded(shouldResume: event.type == platform.AudioInterruptionType.pause);
  }
}
