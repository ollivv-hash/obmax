import 'dart:async';

import 'package:audio_session/audio_session.dart'
    show AndroidAudioManager, AndroidRingerMode;
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
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
/// Nothing here may hold the splash back: [load] never throws and gives up
/// after [loadBudget], in which case the splash runs silent.
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

  /// [load] got the jingle ready and [play] has not been called yet.
  @visibleForTesting
  bool get isReady => _ready;

  /// Prepares the jingle. Completes within [loadBudget] whatever happens;
  /// [play] is then a no-op unless everything went through in time.
  Future<void> load() async {
    if (!isSupported) return;
    try {
      _ready = await _prepare().timeout(loadBudget);
    } catch (e) {
      debugPrint('OB Max splash sound: not played ($e)');
      _ready = false;
    }
    // Too slow or failed: let the preparation finish in the background, then
    // drop the player.
    if (!_ready) unawaited(_release());
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

  /// Starts the jingle, if [load] got it ready. Call it right next to the
  /// timeline's `forward()`.
  void play() {
    final player = _player;
    if (!_ready || _released || player == null) return;
    _ready = false;
    unawaited(
      player.resume().catchError((Object e) {
        debugPrint('OB Max splash sound: play failed ($e)');
      }),
    );
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
          await player.onPlayerComplete.first.timeout(
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
