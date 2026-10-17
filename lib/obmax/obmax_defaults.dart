import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get_it/get_it.dart';
import 'package:jellyfin_preference/jellyfin_preference.dart';
import 'package:server_core/server_core.dart';

import '../auth/repositories/session_repository.dart';
import '../preference/home_section_config.dart';
import '../preference/preference_constants.dart';
import '../preference/user_preferences.dart';
import '../util/game_library.dart';
import '../util/platform_detection.dart';
import 'obmax_features.dart';

/// OB Max forces the language to French, English only standing behind it for
/// a missing string.
const kObMaxLocale = Locale('fr');

/// Settings OB Max fixes rather than lets the user pick. Most are per account
/// in Moonfin, so they are written again each time a session becomes ready,
/// and their tiles are hidden (see ObMaxFeatures).
abstract final class ObMaxDefaults {
  static StreamSubscription<SessionState>? _sessionSub;

  /// Applies the defaults now and after every login or account switch, and
  /// installs the library filter. Called once from `main()` after DI.
  static Future<void> install() async {
    userViewsFilter = filterUserViews;
    await apply();
    _sessionSub ??= GetIt.instance<SessionRepository>().stateStream
        .where((s) => s == SessionState.ready)
        .listen((_) => unawaited(apply()));
  }

  static Future<void> apply() async {
    final prefs = GetIt.instance<UserPreferences>();
    Future<void> force<T>(Preference<T> pref, T value) async {
      if (prefs.get(pref) != value) await prefs.set(pref, value);
    }

    // One OB Max theme, gold TV focus.
    await force(UserPreferences.visualTheme, VisualThemeId.moonfin);
    await force(UserPreferences.customThemeId, '');
    await force(UserPreferences.oledMode, OledMode.off);
    await force(UserPreferences.focusColor, AppTheme.obMaxGold);

    // Navigation buttons of the features OB Max leaves out.
    await force(UserPreferences.showLiveTvButton, false);
    await force(UserPreferences.showSeerrButton, false);
    await force(UserPreferences.showFriendsButton, false);

    // One server, played in-app only.
    await force(UserPreferences.enableMultiServerLibraries, false);
    await force(UserPreferences.useExternalPlayer, false);
    if (PlatformDetection.isAndroid) {
      await force(
        UserPreferences.playbackEnginePreference,
        PlaybackEnginePreference.media3,
      );
    }

    // Home: full-screen media bar with trailers, fixed rows.
    await force(UserPreferences.mediaBarEnabled, true);
    await force(
      UserPreferences.mediaBarMode,
      UserPreferences.mediaBarModeMoonfin,
    );
    await force(UserPreferences.mediaBarTrailerPreview, true);
    await force(UserPreferences.mergeContinueWatchingNextUp, false);
    await force(UserPreferences.mergeRecentRowsByType, false);
    await force(
      UserPreferences.homeSectionsJson,
      HomeSectionConfig.toJsonString(homeSections()),
    );
  }

  /// My Media, Continue watching, Next up, then the latest additions of each
  /// library (Films, Séries, Concerts in the server's library order).
  /// Everything else is off.
  static List<HomeSectionConfig> homeSections() {
    const shown = [
      HomeSectionType.libraryButtons,
      HomeSectionType.resume,
      HomeSectionType.nextUp,
      HomeSectionType.latestMedia,
    ];
    final rest = HomeSectionConfig.defaults()
        .where((c) => c.isBuiltin && !shown.contains(c.type))
        .toList();
    return [
      for (var i = 0; i < shown.length; i++)
        HomeSectionConfig(type: shown[i], enabled: true, order: i),
      for (var i = 0; i < rest.length; i++)
        rest[i].copyWith(enabled: false, order: shown.length + i),
    ];
  }

  static bool _isOffered(Map item) {
    final type = item['CollectionType'] as String?;
    if (!ObMaxFeatures.isCollectionTypeVisible(type)) return false;
    if (ObMaxFeatures.games) return true;
    return !isGameLibrary(
      item['Id']?.toString() ?? '',
      type,
      item['Name'] as String?,
    );
  }

  /// Drops the libraries OB Max does not offer (books, music, live TV) from
  /// every `/UserViews` answer, so they vanish from navigation, My Media,
  /// home rows and pickers alike.
  static Map<String, dynamic> filterUserViews(Map<String, dynamic> response) {
    final items = response['Items'];
    if (items is! List) return response;
    return {
      ...response,
      'Items': [
        for (final item in items)
          if (item is! Map || _isOffered(item)) item,
      ],
    };
  }
}
