import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';

import '../../preference/user_preferences.dart';
import '../../util/platform_detection.dart';

/// OB Max: on macOS, videos can play through mpv (media_kit, as on Windows)
/// instead of AetherEngine.
///
/// AetherEngine reads ahead 8 to 16 MB over the network, a few seconds of a
/// high bitrate film, and stalls over a remote link that a browser plays
/// through. mpv keeps up to 256 MiB ahead on desktop.
///
/// The backends are built once at startup, so the choice applies after a
/// restart: [useMpv] is read once and kept for the app's lifetime.
abstract final class ObMaxMacPlayer {
  static final preference = Preference(
    key: 'obmax_macos_mpv_player',
    defaultValue: false,
  );

  static bool? _useMpv;

  /// mpv plays the videos on this Mac.
  static bool get useMpv => _useMpv ??=
      PlatformDetection.isMacOS &&
      GetIt.instance<UserPreferences>().get(preference);

  /// AetherEngine plays the videos: iOS, and macOS unless mpv was chosen.
  static bool get usesAether =>
      PlatformDetection.isIOS || (PlatformDetection.isMacOS && !useMpv);
}
