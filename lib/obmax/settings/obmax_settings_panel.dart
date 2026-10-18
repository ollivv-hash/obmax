// OB Max settings: only what the user may change (spec §8.3). Built from the
// upstream tiles and screens, which is why this file is a part of the
// settings library rather than an import.
part of '../../ui/screens/settings/settings_side_panel.dart';

List<_PanelEntry> _obMaxPanelEntries(
  BuildContext context, {
  required bool showAdmin,
  required FocusNode? firstFocus,
  required VoidCallback openAdmin,
}) {
  final l10n = AppLocalizations.of(context);
  return [
    if (showAdmin)
      _PanelEntry(
        icon: Icons.admin_panel_settings,
        title: l10n.administration,
        subtitle: l10n.settingsAdministrationSubtitle,
        focusNode: firstFocus,
        onTap: openAdmin,
      ),
    _PanelEntry(
      icon: Icons.lock,
      title: 'Compte et sécurité',
      subtitle: 'Certificat, code PIN, contrôle parental, déconnexion',
      focusNode: showAdmin ? null : firstFocus,
      onTap: () => context.pushSettingsScreen(const _ObMaxAccountScreen()),
    ),
    _PanelEntry(
      icon: Icons.play_circle,
      title: l10n.playback,
      subtitle: 'Langues, sous-titres, qualité, épisode suivant, SyncPlay',
      onTap: () => context.pushSettingsScreen(const _ObMaxPlaybackScreen()),
    ),
    _PanelEntry(
      icon: Icons.palette,
      title: 'Personnalisation',
      subtitle: PlatformDetection.isTV
          ? 'Économiseur d’écran, fiche détaillée, navigation'
          : 'Fiche détaillée, navigation',
      onTap: () =>
          context.pushSettingsScreen(const _ObMaxCustomizationScreen()),
    ),
    _PanelEntry(
      icon: Icons.info_outline,
      title: l10n.aboutTitle,
      subtitle: 'Version, mises à jour, licences',
      onTap: () => context.pushSettingsScreen(const _ObMaxAboutScreen()),
    ),
  ];
}

class _ObMaxAccountScreen extends StatelessWidget {
  const _ObMaxAccountScreen();

  Future<void> _signOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Se déconnecter ?'),
        content: const Text(
          'Vous devrez saisir à nouveau votre identifiant. Le certificat reste '
          'installé sur cet appareil.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          FilledButton(
            autofocus: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Se déconnecter'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await GetIt.instance<SessionRepository>().destroyCurrentSession();
    if (!context.mounted) return;
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    if (rootNavigator.canPop()) rootNavigator.pop();
    appRouter.go(Destinations.serverSelect);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: buildSettingsAppBar(context, const Text('Compte et sécurité')),
      body: ListView(
        children: [
          _SectionHeader('Sécurité'),
          adaptiveListSection(
            children: [
              _TvSettingsListTile(
                autofocus: true,
                leading: const Icon(Icons.verified_user),
                title: const Text('Certificat'),
                subtitle: const Text(
                  'Sujet et date d’expiration, remplacement, suppression',
                ),
                onTap: () => context.pushSettingsScreen(
                  const _ObMaxCertificateScreen(),
                ),
              ),
              _TvSettingsListTile(
                leading: const Icon(Icons.pin),
                title: Text(l10n.pinCode),
                subtitle: Text(l10n.requirePinToAccess),
                onTap: () =>
                    context.pushSettingsScreen(const PinCodeSettingsScreen()),
              ),
              _TvSettingsListTile(
                leading: const Icon(Icons.family_restroom),
                title: Text(l10n.parentalControls),
                subtitle: Text(l10n.contentRatingRestrictions),
                onTap: () =>
                    context.pushSettingsScreen(const ParentalSettingsScreen()),
              ),
            ],
          ),
          _SectionHeader('Session'),
          adaptiveListSection(
            children: [
              _TvSettingsListTile(
                leading: const Icon(Icons.logout),
                title: Text(l10n.signOut),
                subtitle: const Text('Revenir à l’écran de connexion'),
                onTap: () => unawaited(_signOut(context)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ObMaxPlaybackScreen extends StatelessWidget {
  const _ObMaxPlaybackScreen();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final languages = supportedLanguageOptions;
    return withCleanSettingsTypography(
      context,
      Scaffold(
        appBar: buildSettingsAppBar(context, Text(l10n.playback)),
        body: ListView(
          children: [
            _SectionHeader('Langues et sous-titres'),
            adaptiveListSection(
              children: [
                StringPickerPreferenceTile(
                  preference: UserPreferences.defaultAudioLanguage,
                  title: l10n.defaultAudioLanguage,
                  icon: Icons.language,
                  options: {'auto': l10n.autoServerDefault, ...languages},
                ),
                _TvSettingsListTile(
                  leading: const Icon(Icons.subtitles),
                  title: Text(l10n.subtitles),
                  subtitle: const Text(
                    'Langue par défaut et style des sous-titres',
                  ),
                  onTap: () =>
                      context.pushSettingsScreen(const SubtitleSettingsScreen()),
                ),
              ],
            ),
            _SectionHeader('Qualité'),
            adaptiveListSection(
              children: [
                StringPickerPreferenceTile(
                  preference: UserPreferences.maxBitrate,
                  title: l10n.maxStreamingBitrate,
                  description: 'Baissez-le en 4G pour économiser vos données '
                      'et éviter les coupures.',
                  icon: Icons.network_check,
                  options: {
                    'auto': l10n.auto,
                    '120': '120 Mbit/s',
                    '80': '80 Mbit/s',
                    '40': '40 Mbit/s',
                    '20': '20 Mbit/s',
                    '10': '10 Mbit/s',
                    '5': '5 Mbit/s',
                    '2': '2 Mbit/s',
                    '1': '1 Mbit/s',
                  },
                ),
              ],
            ),
            _SectionHeader('Enchaînement'),
            adaptiveListSection(
              children: [
                SwitchPreferenceTile(
                  preference: UserPreferences.autoplayNextEpisode,
                  title: l10n.autoplayNextEpisode,
                  subtitle: l10n.autoplayNextEpisodeSubtitle,
                  icon: Icons.play_circle,
                ),
              ],
            ),
            _SectionHeader(l10n.settingsWatchTogetherSection),
            adaptiveListSection(
              children: [
                _TvSettingsListTile(
                  leading: const Icon(Icons.groups),
                  title: Text(l10n.syncPlay),
                  subtitle: Text(l10n.settingsSyncplaySubtitle),
                  onTap: () => context.pushSettingsScreen(
                    const _SyncPlaySettingsScreen(),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ObMaxCustomizationScreen extends StatelessWidget {
  const _ObMaxCustomizationScreen();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: buildSettingsAppBar(context, const Text('Personnalisation')),
      body: ListView(
        children: [
          adaptiveListSection(
            children: [
              if (PlatformDetection.isTV)
                _TvSettingsListTile(
                  autofocus: true,
                  leading: const Icon(Icons.wallpaper),
                  title: Text(l10n.screensaver),
                  subtitle: Text(l10n.enableBuiltInScreensaver),
                  onTap: () => context.pushSettingsScreen(
                    const ScreensaverSettingsScreen(),
                  ),
                ),
              _TvSettingsListTile(
                autofocus: !PlatformDetection.isTV,
                leading: const Icon(Icons.article_outlined),
                title: Text(l10n.detailsPage),
                subtitle: Text(l10n.settingsDetailsPageSubtitle),
                onTap: () => context.pushSettingsScreen(
                  const _DetailsScreenSettingsScreen(),
                ),
              ),
              _TvSettingsListTile(
                leading: const Icon(Icons.view_sidebar),
                title: Text(l10n.navigationBar),
                subtitle: Text(l10n.navbarStyleToolbarAppearance),
                onTap: () => context.pushSettingsScreen(
                  const _NavigationCategoryScreen(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ObMaxAboutScreen extends StatelessWidget {
  const _ObMaxAboutScreen();

  @override
  Widget build(BuildContext context) {
    final appVersion = GetIt.instance<DeviceInfo>().appVersion;
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: buildSettingsAppBar(context, Text(l10n.aboutTitle)),
      body: ListView(
        children: [
          const SizedBox(height: 24),
          Center(child: Image.asset('assets/obmax/logo.png', height: 96)),
          const SizedBox(height: 8),
          Center(
            child: Text(
              'OB Max $appVersion',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          const SizedBox(height: 16),
          adaptiveListSection(
            children: [
              _TvSettingsListTile(
                autofocus: true,
                leading: const Icon(Icons.info_outline),
                title: Text(l10n.version),
                subtitle: Text(appVersion),
                trailing: const SizedBox.shrink(),
                onTap: () {},
              ),
              if (ObMaxUpdater.isSupported) const _ObMaxCheckForUpdatesTile(),
            ],
          ),
          _SectionHeader(l10n.settingsLegal),
          adaptiveListSection(
            children: [
              _TvSettingsListTile(
                leading: const Icon(Icons.nights_stay_outlined),
                title: const Text('OB Max est basé sur Moonfin (GPL v2)'),
                subtitle: const Text(kObMaxUpstreamUrl),
                onTap: () => showQrOrLaunch(
                  context,
                  url: kObMaxUpstreamUrl,
                  title: 'Moonfin',
                ),
              ),
              _TvSettingsListTile(
                leading: const Icon(Icons.code),
                title: const Text('Code source d’OB Max'),
                subtitle: const Text(kObMaxSourceUrl),
                onTap: () => showQrOrLaunch(
                  context,
                  url: kObMaxSourceUrl,
                  title: 'Code source d’OB Max',
                ),
              ),
              _TvSettingsListTile(
                leading: const Icon(Icons.description),
                title: Text(l10n.settingsLicenses),
                subtitle: Text(l10n.settingsOpenSourceLicenseNotices),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: kObMaxAppName,
                  applicationVersion: appVersion,
                  applicationLegalese:
                      'OB Max est basé sur Moonfin, distribué sous licence '
                      'GNU GPL v2.\n$kObMaxUpstreamUrl',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ObMaxCheckForUpdatesTile extends StatefulWidget {
  const _ObMaxCheckForUpdatesTile();

  @override
  State<_ObMaxCheckForUpdatesTile> createState() =>
      _ObMaxCheckForUpdatesTileState();
}

class _ObMaxCheckForUpdatesTileState extends State<_ObMaxCheckForUpdatesTile> {
  bool _checking = false;

  Future<void> _check() async {
    setState(() => _checking = true);
    await ObMaxUpdater.checkFromSettings(context);
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    return _TvSettingsListTile(
      leading: _checking
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.system_update_alt),
      title: const Text('Rechercher une mise à jour'),
      subtitle: const Text('Vérifie si une nouvelle version d’OB Max existe'),
      onTap: _checking ? null : _check,
    );
  }
}

/// The OB Max server's certificate: where it comes from, its expiry, and the
/// V2 actions (renew now, activate with a new code). The upstream screen
/// stays one tap away for .p12 imports and removal.
class _ObMaxCertificateScreen extends StatefulWidget {
  const _ObMaxCertificateScreen();

  @override
  State<_ObMaxCertificateScreen> createState() =>
      _ObMaxCertificateScreenState();
}

class _ObMaxCertificateScreenState extends State<_ObMaxCertificateScreen> {
  StoredClientCertificate? _certificate;
  ObMaxEnrollment? _enrollment;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final cert = await GetIt.instance<ClientCertificateStore>().get(
      ObMaxEnroller.host,
    );
    final enrollment = await ObMaxEnroller.current();
    if (!mounted) return;
    setState(() {
      _certificate = cert;
      _enrollment = enrollment;
      _loading = false;
    });
  }

  void _snack(String text) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(text)),
    );
  }

  Future<void> _renew() async {
    setState(() => _busy = true);
    try {
      await ObMaxEnroller.renewIfDue(force: true);
      _snack('Certificat renouvelé.');
    } on ObMaxEnrollException catch (e) {
      _snack(e.message);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _load();
  }

  Future<void> _activateWithCode() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Activer avec un code'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Code d’invitation',
            hintText: 'XXXX-XXXX-XXXX',
          ),
          onSubmitted: (v) => Navigator.of(context).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppLocalizations.of(context).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Activer'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.trim().isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      await ObMaxEnroller.enroll(code);
      _snack('Cet appareil a un nouveau certificat OB Max.');
    } on ObMaxEnrollException catch (e) {
      _snack(e.message);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    await _load();
  }

  String _date(DateTime d) {
    final l = d.toLocal();
    return '${l.day.toString().padLeft(2, '0')}/'
        '${l.month.toString().padLeft(2, '0')}/${l.year}';
  }

  @override
  Widget build(BuildContext context) {
    final cert = _certificate;
    final enrollment = _enrollment;
    return Scaffold(
      appBar: buildSettingsAppBar(context, const Text('Certificat')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                _SectionHeader('Certificat de cet appareil'),
                adaptiveListSection(
                  children: [
                    _TvSettingsListTile(
                      autofocus: true,
                      leading: const Icon(Icons.verified_user),
                      title: Text(
                        cert == null ? 'Aucun certificat' : cert.subject,
                      ),
                      subtitle: Text(
                        cert == null
                            ? 'OB Max demandera un code au prochain démarrage.'
                            : 'Expire le ${_date(cert.notAfter)} · '
                                  '${enrollment != null ? 'délivré par OB Max, renouvelé automatiquement' : 'importé depuis un fichier .p12'}',
                      ),
                      trailing: const SizedBox.shrink(),
                      onTap: () {},
                    ),
                  ],
                ),
                _SectionHeader('Actions'),
                adaptiveListSection(
                  children: [
                    if (enrollment != null)
                      _TvSettingsListTile(
                        leading: const Icon(Icons.autorenew),
                        title: const Text('Renouveler maintenant'),
                        subtitle: const Text(
                          'Normalement automatique, 60 jours avant l’expiration',
                        ),
                        onTap: _busy ? null : () => unawaited(_renew()),
                      ),
                    _TvSettingsListTile(
                      leading: const Icon(Icons.key),
                      title: const Text('Activer avec un nouveau code'),
                      subtitle: const Text(
                        'Remplace le certificat par un nouveau, délivré par OB Max',
                      ),
                      onTap: _busy ? null : () => unawaited(_activateWithCode()),
                    ),
                    _TvSettingsListTile(
                      leading: const Icon(Icons.folder_open),
                      title: const Text('Gérer les certificats (avancé)'),
                      subtitle: const Text(
                        'Importer un fichier .p12, supprimer un certificat',
                      ),
                      onTap: () async {
                        await context.pushSettingsScreen(
                          const _ClientCertificatesScreen(),
                        );
                        if (mounted) await _load();
                      },
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
