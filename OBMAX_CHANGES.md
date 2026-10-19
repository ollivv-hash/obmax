# OB Max — guide de rebase

Liste des fichiers **upstream** modifiés par OB Max, avec la raison. Tout ce qui est propre à OB Max vit dans `lib/obmax/`, `tools/`, les `res/` des flavors Android et les fichiers `OBMAX_*.md` : ces fichiers ne sont pas listés ici, ils ne peuvent pas entrer en conflit.

Chaque modification dans le code upstream est un point d'accroche court, marqué `// OBMAX:` (ou `# OBMAX:`). Après un rebase, `git grep -n OBMAX` doit retrouver toutes les lignes de ce tableau.

## Procédure de rebase

```powershell
git fetch upstream
git rebase upstream/main obmax/main
# En cas de conflit sur lib/l10n/app_localizations*.dart : prendre la version upstream,
# puis régénérer (ces fichiers sont produits par `flutter gen-l10n` depuis les .arb).
git checkout --theirs lib/l10n/app_localizations*.dart   # pendant le rebase, "theirs" = nos commits
. .\tools\obmax_env.ps1; & $script:Flutter gen-l10n
```

Les deux premiers commits d'`obmax/main` sont identiques aux branches `upstream-pr/*`. Ils ont été fusionnés upstream le 18/10/2026 (#1893 et #1894) : la prochaine synchronisation avec `upstream/main` les rendra redondants, puis ces deux lignes pourront sortir du tableau.

## Fichiers upstream modifiés

| Fichier | Raison |
|---|---|
| `.gitignore` | Certificats, clés, keystores et `key.properties` jamais dans git ; sorties de `tools/release.ps1` (`/dist/`). |
| `packages/server_core/lib/src/network/client_certificates_io.dart` | Correctif WebSocket port 0 (PR `upstream-pr/ws-port0`). |
| `lib/ui/screens/auth/server_select_screen.dart` | Import du certificat proposé pour le premier candidat https (PR `upstream-pr/mtls-onboarding`). |
| `android/app/build.gradle.kts` | `applicationId` privé, lu dans `android/obmax.properties` (écrit par `tools/obmax_private.ps1`, ignoré par git), et nom « OB Max » pour les deux flavors ; plugin `google-services` désactivé (push Firebase coupé). |
| `android/app/build.gradle.kts` (bis) | `storeFile=` dans `keystore.properties` peut désigner un keystore hors du dépôt. |
| `pubspec.yaml` | Version OB Max `1.0.0+1` (et `android_tv_version` / `android_tv_build_number`, lus par Gradle pour la flavor TV). Mise à jour par `tools/release.ps1`. |
| `lib/di/injection.dart` | Nom de client envoyé à Jellyfin (`X-Emby-Authorization`) = « OB Max ». |
| `packages/server_core/lib/src/network/server_user_agent.dart` | User-agent `OBMax/<version>` dans les logs serveur. |
| `lib/data/services/push_messaging_service.dart` | Push Firebase désactivé (`ObMaxFeatures.pushMessaging`). |
| `lib/data/services/certificate_upload_server.dart` | Page d'envoi du `.p12` depuis le téléphone : version OB Max en français. |
| `lib/l10n/app_fr.arb`, `app_en.arb`, `app_en_GB.arb` | « Moonfin » → « OB Max » dans les textes visibles (sauf URL et chemins `Téléchargements/Moonfin`, qui désignent un vrai dossier). |
| `lib/l10n/app_localizations*.dart` | Générés depuis les `.arb`. Ne jamais les fusionner à la main : régénérer. |
| `lib/main.dart` | `ObMaxBoot.showSplash()` juste après l'init du binding, et `ObMaxBoot.finish(app)` à la place du `runApp` final : le splash animé tourne pendant toute l'initialisation. |
| `lib/ui/screens/auth/startup_screen.dart` | Affiche la dernière image du splash pendant la restauration de session ; sans certificat valide (supprimé, expiré), va directement à la porte OB Max ; passe toujours par la porte OB Max (jamais par l'écran utilisateurs d'un serveur mémorisé). |
| `lib/ui/navigation/app_router.dart` | La route `serverSelect` ouvre `ObMaxOnboardingScreen` (certificat → test → serveur) : tous les flux upstream qui renvoient vers la sélection de serveur (reconnexion, session expirée, PIN oublié) arrivent sur la porte OB Max. Route Emby Connect redirigée. |
| `lib/ui/screens/auth/server_screen.dart` | Bouton « Sélectionner un serveur » masqué. |
| `pubspec.yaml` (assets) | Déclare `assets/obmax/` et `assets/obmax/splash/`. |
| `packages/design/lib/src/theme/theme_registry.dart` | `ThemeRegistry.forcedTheme` : toute résolution de thème renvoie le thème OB Max (installé par `ObMaxTheme.install()`). |
| `lib/app.dart` | `ObMaxTheme.adapt()` autour du `ThemeData` (secondaire, tertiaire, textes secondaires, progression bleue…) ; `_resolveLocale()` renvoie toujours `fr`. |
| `lib/preference/preference_constants.dart` | Valeur `AppTheme.obMaxGold` ajoutée en fin d'enum (couleur du focus TV). |
| `lib/main.dart` | `ObMaxDefaults.install()` après `configureDependencies()` : préférences forcées (thème, focus or, Media3, media bar bandes-annonces, sections d'accueil, pas de multi-serveur ni de lecteur externe), réappliquées à chaque session prête. |
| `packages/server_core/lib/src/api/user_views_api.dart`, `packages/server_jellyfin/lib/src/api/jellyfin_user_views_api.dart` | Filtre global `userViewsFilter` appliqué à chaque réponse `/UserViews` : OB Max y retire les bibliothèques Livres, Musique et Live TV, qui disparaissent partout (navigation, Mes médias, rangées, sélecteurs). |
| `lib/ui/widgets/top_toolbar.dart` | Logo OB Max à la place de l'avatar en haut à gauche (il ouvre toujours le menu utilisateur) ; focus doré sur TV. |
| `lib/ui/screens/home/home_screen.dart`, `lib/ui/screens/detail/item_detail_screen.dart` | Voile dégradé `#080A23` 70 % → transparent sur les fonds flous (`ObMaxBackdropVeil`). |
| `lib/ui/navigation/app_router.dart` (bis) | Garde de routes `ObMaxFeatures.isRouteBlocked` (musique, livres, jeux, Live TV, Seerr, lecteur externe → accueil, liens profonds compris) ; assistant de premier lancement désactivé. |
| `lib/di/modules/app_module.dart` | Fournisseurs Google Cast, AirPlay et DLNA non enregistrés (incompatibles mTLS). « Lire sur » une autre session Jellyfin reste possible. |
| `lib/ui/screens/detail/detail_buttons.dart`, `lib/ui/screens/detail/item_detail_screen.dart`, `lib/ui/screens/playback/osd_buttons.dart`, `lib/ui/screens/playback/video_player_screen.dart` | Boutons Cast masqués (fiche et lecteur). |
| `lib/playback/mpv_client_certificate.dart` | Bug n°3 du spike : `tls-verify=yes` + `tls-ca-file` (`lib/obmax/playback/mpv_ca_bundle.dart`) quand un certificat client est présenté. Le fichier d'autorités vient du système (Android, magasin Windows via crypt32, trousseau macOS, bundle Linux), complété par `assets/obmax/tls-roots.pem` (ISRG X1/X2, USERTrust). Sans lui, l'OpenSSL de libmpv sur Windows refuse le serveur (`0A000086`) et aucun film ne se lance. |
| `lib/ui/navigation/app_router.dart`, `lib/ui/screens/settings/settings_side_panel.dart` (admin) | Administration ouverte aux admins Jellyfin sur Android TV aussi (`ObMaxFeatures.adminOnTv`) ; Moonfin n'a pas de mise en page TV pour ces écrans. |
| `lib/ui/screens/settings/settings_side_panel.dart` (V2) | Import de `obmax_enrollment.dart`, utilisé par l'écran « Certificat » du panneau OB Max (code d'invitation, renouvellement). |
| `lib/ui/screens/settings/settings_side_panel.dart` | `part` du panneau OB Max (`lib/obmax/settings/obmax_settings_panel.dart`) à la place des catégories Moonfin ; recherche des réglages masquée (elle atteignait les réglages cachés). |
| `lib/ui/widgets/user_menu_dialog.dart` | Plus de « Sélectionner un serveur » ni de « Déconnecter tous les utilisateurs » (qui supprimait le serveur, et avec lui le certificat). |
| `lib/ui/widgets/playback/player_loading_overlay.dart` | Chargement de la lecture : logo OB Max qui tourne sur lui-même avec un halo doré, et libellé en français (« Chargement… ») au lieu du texte anglais en dégradé Moonfin (`ObMaxLoadingOverlay`). |
| `android/app/src/main/kotlin/org/moonfin/androidtv/MainActivity.kt` | Enregistre `ObMaxInstaller` (canal `obmax/installer`) pour l'OTA. |
| `android/app/src/main/AndroidManifest.xml` | Permission `REQUEST_INSTALL_PACKAGES` (OTA). |
| `assets/images/logo_and_text.png` | Remplacé par le logo OB Max (même format 1179×266) : il est affiché par les écrans de connexion, l'économiseur d'écran et l'À propos upstream. En cas de conflit au rebase, garder la version OB Max. |
| `ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png` | Icône OB Max (générée depuis `obmax_ipad_1024.png`, sans canal alpha). |
| `macos/Runner/Configs/AppInfo.xcconfig` | App Mac « OB Max », copyright ; l'identifiant vient de `ObMaxPrivate.xcconfig` (privé, ignoré par git). |
| `macos/Runner/Assets.xcassets/AppIcon.appiconset/*.png` | Icône OB Max au gabarit macOS (carré arrondi avec ombre, généré depuis l'icône iOS). |
| `build-macos.sh` | `APP_NAME="OB Max"` (nom du `.app` et du `.dmg`). |
| `lib/auth/store/client_certificate_store_io.dart` | Index des hôtes (`mtls_client_cert_hosts`) et relecture un par un quand `readAll` échoue : sur macOS, le trousseau classique refuse `readAll` (errSecParam -50), le certificat était enregistré mais jamais rechargé. Mises à jour de l'index sérialisées, index écrit avant le certificat (remarques CodeRabbit). Proposé à Moonfin : PR #1930 ; une fois fusionnée, reprendre la version upstream. |
| `windows/runner/Runner.rc`, `windows/runner/main.cpp` | App Windows « OB Max » (ressource de version, titre de fenêtre). L'exécutable garde le nom `moonfin.exe`. |
| `windows/runner/resources/app_icon.ico` | Icône OB Max (carré arrondi, 16 à 256 px). |
| `build-windows.ps1` | Installateur OB Max : nom, éditeur, dossier `OB Max`, `AppId` propre (n'écrase ni ne désinstalle jamais Moonfin), assistant en français, fichier `obmax-windows-<version>.exe`. |
| `lib/data/services/app_update_service.dart` | Le vérificateur de mises à jour desktop (DMG) lit les releases OB Max (`kObMaxReleasesRepo`) au lieu de celles de Moonfin. |

## Ressources ajoutées (pas de conflit possible)

- `android/app/src/mobile/res/`, `android/app/src/androidTv/res/` : icônes OB Max (mipmaps, adaptive icon sur fond `#080A23`). Elles remplacent celles de `main/res` pour les flavors `mobile` et `androidTv`. La bannière TV est copiée sous le nom upstream `drawable-nodpi/moonfin_tv_banner.png` : le manifest (`android:banner="@drawable/moonfin_tv_banner"`) reste inchangé.
- Le splash natif Android 12+ (`values-v31/styles.xml`) utilise déjà `@color/ic_launcher_background` et `@mipmap/ic_launcher_foreground` : il passe automatiquement à `#080A23` + icône OB Max, sans modifier les styles.

- `.github/README.md` : page d'accueil OB Max du dépôt. GitHub l'affiche à la place du `README.md` de Moonfin, qui reste inchangé.
- `docs/obmax/` : publication (`RELEASE.md`), conception de l'activation (`V2_SPEC.md`), recette (`TEST_CHECKLIST.md`), guide des invités (`guide-installation.html`).
- `.github/workflows/obmax-macos.yml` : build du `.dmg` macOS. Les workflows de Moonfin restent dans le dépôt mais sont désactivés dans les réglages GitHub Actions d'`ollivv-hash/obmax`.

## Valeurs privées (hors dépôt)

Le domaine du serveur et l'identifiant d'app désignent le propriétaire : ils ne sont pas dans git. `tools/obmax_private.ps1 -ServerUrl … -EnrollUrl … -AppId …` écrit `lib/obmax/obmax_private.dart`, `android/obmax.properties` et `macos/Runner/Configs/ObMaxPrivate.xcconfig` (modèle : `tools/obmax_private.dart.example`). Les workflows macOS et Windows font de même à partir des secrets `OBMAX_SERVER_URL`, `OBMAX_ENROLL_URL` et `OBMAX_APP_ID` d'`ollivv-hash/obmax`. Le service d'activation lit `PUBLIC_SERVER_URL` dans `server/enroll/.env`, également ignoré.

## Code OB Max hors `lib/obmax/`

- `android/app/src/main/kotlin/org/moonfin/androidtv/obmax/ObMaxInstaller.kt` : installation des mises à jour via `PackageInstaller`.

## Écarts assumés par rapport à la spec

- **OTA** : `lib/data/services/app_update_service.dart` n'est pas modifié. Il ne sait qu'ouvrir une page de release (desktop) et reste inactif dans OB Max (aucun `DISTRIBUTION_CHANNEL` n'est passé au build). Le service OB Max (`lib/obmax/ota/obmax_updater.dart`) lit `version.json`, télécharge, vérifie le SHA-256 et installe : réécrire le service upstream aurait créé un gros diff à chaque rebase.
