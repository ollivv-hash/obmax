import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moonfin/obmax/splash/obmax_splash_sound.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The splash must never wait on the jingle: whatever goes wrong, load()
// completes within its budget and play() stays silent.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ringer = MethodChannel('com.ryanheise.android_audio_manager');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.android);
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(ringer, null);
  });

  Future<ObMaxSplashSound> load() async {
    final sound = ObMaxSplashSound();
    final watch = Stopwatch()..start();
    await sound.load();
    expect(
      watch.elapsed,
      lessThan(ObMaxSplashSound.loadBudget + const Duration(milliseconds: 200)),
    );
    return sound;
  }

  test('switched off in the settings: no jingle', () async {
    SharedPreferences.setMockInitialValues({
      ObMaxSplashSound.preference.key: false,
    });
    final sound = await load();
    expect(sound.isReady, isFalse);
    sound.play();
    await sound.finish(fade: true);
  });

  test('phone in silent or vibrate mode: no jingle', () async {
    SharedPreferences.setMockInitialValues({});
    for (final mode in [0, 1]) {
      messenger.setMockMethodCallHandler(ringer, (call) async {
        expect(call.method, 'getRingerMode');
        return mode;
      });
      final sound = await load();
      expect(sound.isReady, isFalse, reason: 'ringer mode $mode');
    }
  });

  test('no audio backend: the splash runs silent, without waiting', () async {
    SharedPreferences.setMockInitialValues({});
    final sound = await load();
    expect(sound.isReady, isFalse);
    sound.play();
    await sound.finish(fade: false);
  });

  test('slow load: returns within budget, a late failure stays silent', () async {
    SharedPreferences.setMockInitialValues({});
    messenger.setMockMethodCallHandler(ringer, (call) async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      return 2; // normal
    });
    final sound = await load();
    expect(sound.isReady, isFalse);
    // The animation starts while the jingle is still loading.
    sound.play();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(sound.isReady, isFalse);
    await sound.finish(fade: false);
  });

  group('on screen', () {
    final binding = TestWidgetsFlutterBinding.instance;
    TestFlutterView view() =>
        binding.platformDispatcher.views.single;
    tearDown(() => view().resetPhysicalSize());

    test('started by a media key, no window: no jingle', () async {
      view().physicalSize = Size.zero;
      final watch = Stopwatch()..start();
      expect(await ObMaxSplashSound.isOnScreen(), isFalse);
      expect(watch.elapsed, lessThan(const Duration(seconds: 1)));
    });

    test('the window gets its size in time: jingle', () async {
      view().physicalSize = Size.zero;
      Timer(
        const Duration(milliseconds: 100),
        () => view().physicalSize = const Size(1920, 1080),
      );
      expect(await ObMaxSplashSound.isOnScreen(), isTrue);
    });

    test('window already on screen: no wait', () async {
      view().physicalSize = const Size(1920, 1080);
      final watch = Stopwatch()..start();
      expect(await ObMaxSplashSound.isOnScreen(), isTrue);
      expect(watch.elapsed, lessThan(const Duration(milliseconds: 50)));
    });

    test('desktop starts always have a window', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      view().physicalSize = Size.zero;
      expect(await ObMaxSplashSound.isOnScreen(), isTrue);
    });
  });

  test('not on Linux', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    expect(ObMaxSplashSound.isSupported, isFalse);
  });
}
