// OB Max: which Moonfin features this build shows. Upstream code asks here
// through short `// OBMAX:` hooks instead of growing its own conditions, so a
// rebase only has to keep the hooks in place.

abstract final class ObMaxFeatures {
  /// Animated OB Max splash at cold start (see ObMaxBoot).
  static const splash = true;

  /// Firebase push needs Moonfin's Firebase project, which OB Max is not part of.
  static const pushMessaging = false;

  /// One fixed server: no server list, no "add" or "change server", no
  /// unified multi-server library.
  static const serverSwitching = false;

  /// Jellyfin only: Emby Connect and Emby detection are off.
  static const emby = false;

  /// Library kinds removed from navigation and libraries.
  static const books = false;
  static const music = false;
  static const liveTv = false;
  static const games = false;

  /// Requests through Seerr, relayed by the Moonbase plugin inside Jellyfin
  /// (/Moonfin/Seerr/...), so it rides on the same mTLS host.
  static const seerr = true;

  /// The receiver or external app fetches the stream itself, without the
  /// client certificate, so these can never work behind mTLS.
  static const cast = false;
  static const externalPlayer = false;

  /// Android plays through Media3 only (the path validated with mTLS).
  static const playbackEngineChoice = false;

  /// One OB Max theme, no theme, accent or theme store choice.
  static const themeChoice = false;

  /// The OB Max logo replaces the user's avatar at the top left (it still
  /// opens the user menu).
  static const toolbarLogo = true;

  /// The admin area for Jellyfin admins on Android TV too. Moonfin has no TV
  /// layout for it, so it is usable but not tuned for the remote.
  static const adminOnTv = true;

  /// The player's loading overlay shows the spinning OB Max logo and a French
  /// label (see ObMaxLoadingOverlay).
  static const loadingOverlay = true;

  /// Moonfin's first-run wizard asks for what OB Max fixes.
  static const setupWizard = false;

  /// The trimmed OB Max settings panel (see obmax_settings_panel.dart): only
  /// what the user may change, no settings search.
  static const settingsPanel = true;

  /// Home rows are fixed (see ObMaxDefaults.homeSections).
  static const homeSectionsEditor = false;

  /// Collection types (Jellyfin `CollectionType`) hidden everywhere. Music
  /// videos stay: the Concerts library may use that type.
  static const hiddenCollectionTypes = <String>{'books', 'music', 'livetv'};

  /// Routes of the features above. The router sends them home, so a deep
  /// link or a leftover entry point cannot reach them.
  static const _blockedRoutePrefixes = [
    '/music/',
    '/books/',
    '/player/book/',
    '/games/',
    '/game/',
    '/game-player/',
    '/live-tv',
    if (!seerr) '/seerr',
    '/player/external',
  ];

  static bool isRouteBlocked(String path) =>
      _blockedRoutePrefixes.any(path.startsWith);

  static bool isCollectionTypeVisible(String? collectionType) =>
      !hiddenCollectionTypes.contains(collectionType?.toLowerCase());
}
