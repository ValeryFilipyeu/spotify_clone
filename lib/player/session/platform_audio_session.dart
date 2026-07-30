import 'dart:async';

import 'package:audio_session/audio_session.dart' as platform;

import 'playback_audio_session.dart';

/// The real OS audio session, backed by audio_session. The only file that
/// imports it -- same containment rule as just_audio and audio_service.
class PlatformAudioSession implements PlaybackAudioSession {
  PlatformAudioSession._(this._session, this.interruptions);

  static Future<PlatformAudioSession> create() async {
    final session = await platform.AudioSession.instance;

    // Nothing else in the stack does this. Verified: audio_service's iOS plugin
    // only touches [AVAudioSession sharedInstance], and just_audio's native code
    // never calls setCategory/setActive at all. Without it iOS leaves us on the
    // default category, which mixes with other apps -- so another app's audio
    // plays over ours and no interruption is ever delivered.
    //
    // music() is the documented preset for a music player: category .playback on
    // iOS (also what background audio requires), and media/music attributes with
    // a full audio-focus gain on Android.
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

  // On Android this is also what requests audio focus, and audio_session only
  // reports focus changes for a request it made -- so without activate() there
  // are no Android interruptions at all, not merely a wrong category.
  @override
  Future<void> activate() => _session.setActive(true);

  @override
  Future<void> deactivate() => _session.setActive(false);

  static AudioInterruption _translate(platform.AudioInterruptionEvent event) {
    if (event.begin) {
      return AudioInterruptionBegan(duck: event.type == platform.AudioInterruptionType.duck);
    }
    // `pause` means a definite interruption that has now finished (a call
    // ending), so picking playback back up is expected. `unknown` means the
    // platform will not vouch for that, and `duck` never stopped us at all.
    return AudioInterruptionEnded(
      shouldResume: event.type == platform.AudioInterruptionType.pause,
    );
  }
}
