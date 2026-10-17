// OB Max: which Moonfin features this build shows. Upstream code asks here
// through short `// OBMAX:` hooks instead of growing its own conditions, so a
// rebase only has to keep the hooks in place.

abstract final class ObMaxFeatures {
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
  static const seerr = false;

  /// The receiver or external app fetches the stream itself, without the
  /// client certificate, so these can never work behind mTLS.
  static const cast = false;
  static const externalPlayer = false;

  /// Android plays through Media3 only (the path validated with mTLS).
  static const playbackEngineChoice = false;

  /// One OB Max theme, no theme, accent or theme store choice.
  static const themeChoice = false;

  /// Home rows are fixed (see ObMaxHome).
  static const homeSectionsEditor = false;

  /// Collection types (Jellyfin `CollectionType`) hidden everywhere. Music
  /// videos stay: the Concerts library may use that type.
  static const hiddenCollectionTypes = <String>{'books', 'music', 'livetv'};

  static bool isCollectionTypeVisible(String? collectionType) =>
      !hiddenCollectionTypes.contains(collectionType?.toLowerCase());
}
