import 'dart:async';

import 'package:audio_session/audio_session.dart'
    show AndroidAudioManager, AndroidRingerMode;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../util/platform_detection.dart';

/// The OB Max jingle played with the cold start splash (spec
/// docs/obmax/SON_SPLASH_SPEC.md).
///
/// The timing lives in the file (first "ah" at 0.72 s with the star, the
/// impact at 0.98 s with OB / MAX), so [play] is called in the same frame as
/// the splash timeline's `forward()`, with no offset.
///
/// Nothing here may hold the splash back: [load] never throws and returns
/// within [loadBudget]. A jingle still loading by then keeps loading, and
/// [play] starts it late, seeked to where the animation is, as long as that
/// is within [lateStartLimit] (leading silence only). Past that, or on any
/// failure, the splash runs silent.
class ObMaxSplashSound {
  /// "Son au démarrage", on by default everywhere.
  static final preference = Preference(
    key: 'obmax_splash_sound',
    defaultValue: true,
  );

  /// Relative to audioplayers' asset prefix (`assets/`).
  static const _asset = 'obmax/splash/obmax_splash.m4a';

  /// Vorbis copy, for a backend that turns the AAC file down.
  static const _fallbackAsset = 'obmax/splash/obmax_splash.ogg';

  static const loadBudget = Duration(milliseconds: 300);

  /// How late the jingle may still start, seeked into the file. The first
  /// sound is at 0.72 s, so up to here only leading silence is skipped and
  /// nothing is heard out of sync. A Shield needs more than [loadBudget] at
  /// cold start (the asset is copied to a temporary file, then prepared).
  static const lateStartLimit = Duration(milliseconds: 700);

  static const fadeOut = Duration(milliseconds: 150);

  /// The jingle is 2.6 s long; past this the player is released regardless.
  static const _maxPlayTime = Duration(milliseconds: 3200);

  /// Android, Android TV, Windows, macOS, iOS. Off on the web (autoplay is
  /// blocked before a user gesture), on Linux (no backend, see
  /// packages/audioplayers_linux_disabled) and on Apple TV (no tvOS plugin).
  static bool get isSupported =>
      !kIsWeb &&
      !PlatformDetection.isAppleTV &&
      (PlatformDetection.isAndroid ||
          PlatformDetection.isIOS ||
          PlatformDetection.isMacOS ||
          PlatformDetection.isWindows);

  AudioPlayer? _player;
  bool _ready = false;
  bool _released = false;

  /// Still loading after [loadBudget]: completes with whether it got ready.
  Future<bool>? _pending;

  /// [load] got the jingle ready and [play] has not been called yet.
  @visibleForTesting
  bool get isReady => _ready;

  /// Prepares the jingle. Completes within [loadBudget] whatever happens.
  Future<void> load() async {
    if (!isSupported) return;
    final watch = Stopwatch()..start();
    final preparing = _prepare().then(
      (ready) {
        if (ready) {
          debugPrint(
            'OB Max splash sound: ready in ${watch.elapsedMilliseconds} ms',
          );
        }
        return ready;
      },
      onError: (Object e) {
        debugPrint('OB Max splash sound: not played ($e)');
        return false;
      },
    );
    try {
      _ready = await preparing.timeout(loadBudget);
      if (!_ready) unawaited(_release());
    } on TimeoutException {
      // Keeps loading; play() decides whether it can still start in sync.
      _pending = preparing;
    }
  }

  Future<bool> _prepare() async {
    if (!await _enabled()) return false;
    // Phone in silent or vibrate mode: no jingle. Android TV boxes report
    // the normal mode, so this only ever mutes a phone or a tablet.
    if (PlatformDetection.isAndroid &&
        await AndroidAudioManager().getRingerMode() !=
            AndroidRingerMode.normal) {
      return false;
    }
    if (_released) return false;
    final player = _player = AudioPlayer();
    await player.setReleaseMode(ReleaseMode.stop);
    await player.setAudioContext(
      AudioContext(
        // Media stream, and no audio focus at all: music playing in another
        // app is neither stopped nor ducked.
        android: const AudioContextAndroid(
          usageType: AndroidUsageType.media,
          contentType: AndroidContentType.sonification,
          audioFocus: AndroidAudioFocus.none,
        ),
        // Ambient follows the silent switch and mixes with other audio.
        iOS: AudioContextIOS(category: AVAudioSessionCategory.ambient),
      ),
    );
    try {
      await player.setSource(AssetSource(_asset));
    } catch (e) {
      debugPrint('OB Max splash sound: AAC refused ($e), trying Vorbis');
      await player.setSource(AssetSource(_fallbackAsset));
    }
    return !_released;
  }

  /// Reads the switch straight from shared preferences: the splash runs
  /// before DI, so UserPreferences is not there yet. Same key, same store.
  static Future<bool> _enabled() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.get(preference.key);
    if (value is bool) return value;
    if (value is String) return value.toLowerCase() != 'false';
    return preference.defaultValue;
  }

  /// Starts the jingle, if [load] got it ready and the app is on screen.
  /// Call it right next to the timeline's `forward()`.
  void play() {
    if (_released) return;
    final Future<bool> loaded;
    if (_ready && _player != null) {
      loaded = Future.value(true);
    } else if (_pending case final pending?) {
      loaded = pending;
    } else {
      return;
    }
    _ready = false;
    _pending = null;
    final sinceStart = Stopwatch()..start();
    unawaited(
      Future.wait([loaded, isOnScreen()]).then((results) async {
        final player = _player;
        if (!results[0] || _released || player == null) return _release();
        if (!results[1]) {
          debugPrint('OB Max splash sound: app not on screen, not played');
          return _release();
        }
        final late = sinceStart.elapsed;
        if (late > lateStartLimit) {
          debugPrint(
            'OB Max splash sound: ready ${late.inMilliseconds} ms after '
            'the animation started, not played',
          );
          return _release();
        }
        await _start(player, late < _onTime ? Duration.zero : late);
      }),
    );
  }

  /// Below this, a start counts as on time and is not seeked.
  static const _onTime = Duration(milliseconds: 40);

  /// Whether the app has a window on screen, waiting up to [lateStartLimit]
  /// for one to get a size.
  ///
  /// On Android a play/pause key can start OB Max with no screen at all:
  /// once OB Max has played something, Android sends it the media keys no
  /// other app takes, and audio_service's receiver then runs `main()` in the
  /// background, splash included. That engine's view stays 0x0 (seen on a
  /// Shield, which reports 1920x1080 for a launch from the home screen).
  /// The lifecycle state can't tell them apart: a visible launch also stays
  /// paused, the engine being created by audio_service before the activity.
  /// Elsewhere every start comes with a window.
  @visibleForTesting
  static Future<bool> isOnScreen() async {
    if (!PlatformDetection.isAndroid) return true;
    final binding = WidgetsBinding.instance;
    bool hasWindow() => binding.platformDispatcher.views.any(
      (view) => !view.physicalSize.isEmpty,
    );
    if (hasWindow()) return true;
    final sized = Completer<bool>();
    final observer = _MetricsObserver(() {
      if (hasWindow() && !sized.isCompleted) sized.complete(true);
    });
    binding.addObserver(observer);
    try {
      return await sized.future.timeout(
        lateStartLimit,
        onTimeout: () => false,
      );
    } finally {
      binding.removeObserver(observer);
    }
  }

  /// Starts [player] at [position] into the jingle.
  Future<void> _start(AudioPlayer player, Duration position) async {
    try {
      if (position > Duration.zero) await player.seek(position);
      if (_released) return;
      await player.resume();
    } catch (e) {
      debugPrint('OB Max splash sound: play failed ($e)');
    }
  }

  /// The splash is going away. With [fade] (skipped by a key or a tap) the
  /// jingle fades out over [fadeOut] and stops; otherwise it is left to end
  /// by itself. The player is released either way.
  Future<void> finish({required bool fade}) async {
    final player = _player;
    if (_released) return;
    // Still loading: marking it released makes the load give up.
    if (player == null) return _release();
    try {
      if (player.state == PlayerState.playing) {
        if (fade) {
          const steps = 6;
          for (var i = steps - 1; i >= 0; i--) {
            await Future<void>.delayed(fadeOut ~/ steps);
            await player.setVolume(i / steps);
          }
          await player.stop();
        } else {
          // then<void>: the stream's runtime type is not void, and a
          // void onTimeout on it throws, which used to cut the tail.
          await player.onPlayerComplete.first.then<void>((_) {}).timeout(
            _maxPlayTime,
            onTimeout: () {},
          );
        }
      }
    } catch (e) {
      debugPrint('OB Max splash sound: stop failed ($e)');
    }
    await _release();
  }

  Future<void> _release() async {
    if (_released) return;
    _released = true;
    _ready = false;
    final player = _player;
    _player = null;
    try {
      await player?.dispose();
    } catch (_) {}
  }
}

class _MetricsObserver with WidgetsBindingObserver {
  _MetricsObserver(this.onChange);

  final VoidCallback onChange;

  @override
  void didChangeMetrics() => onChange();
}
