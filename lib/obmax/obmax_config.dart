// OB Max build configuration. Everything that makes this fork OB Max rather
// than Moonfin is decided here or in the files next to it, so upstream code
// only carries short `// OBMAX:` hooks.

/// The only server this build talks to.
const kObMaxServerUrl = String.fromEnvironment(
  'OBMAX_SERVER_URL',
  defaultValue: 'https://jellyfin.example.com',
);

/// Public GitHub repository holding the release APKs and `version.json`.
const kObMaxReleasesRepo = String.fromEnvironment(
  'OBMAX_RELEASES_REPO',
  defaultValue: 'ollivv-hash/obmax-releases',
);

/// Name shown to the user and sent to Jellyfin as the client name.
const kObMaxAppName = 'OB Max';

/// GPL v2: where OB Max comes from and where its own source lives.
const kObMaxUpstreamUrl = 'https://github.com/Moonfin-Client/Moonfin-Core';
const kObMaxSourceUrl = String.fromEnvironment(
  'OBMAX_SOURCE_URL',
  defaultValue: 'https://github.com/ollivv-hash/obmax',
);
