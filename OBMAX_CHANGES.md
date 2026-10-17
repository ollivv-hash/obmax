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

Les deux premiers commits d'`obmax/main` sont identiques aux branches `upstream-pr/*`. S'ils sont acceptés upstream, le rebase les élimine.

## Fichiers upstream modifiés

| Fichier | Raison |
|---|---|
| `.gitignore` | Certificats, clés, keystores et `key.properties` jamais dans git ; sorties de `tools/release.ps1` (`/dist/`). |
| `packages/server_core/lib/src/network/client_certificates_io.dart` | Correctif WebSocket port 0 (PR `upstream-pr/ws-port0`). |
| `lib/ui/screens/auth/server_select_screen.dart` | Import du certificat proposé pour le premier candidat https (PR `upstream-pr/mtls-onboarding`). |
| `android/app/build.gradle.kts` | `applicationId` `com.example.obmax` et nom « OB Max » pour les deux flavors ; plugin `google-services` désactivé (push Firebase coupé). |
| `pubspec.yaml` | Version OB Max `1.0.0+1` (et `android_tv_version` / `android_tv_build_number`, lus par Gradle pour la flavor TV). Mise à jour par `tools/release.ps1`. |
| `lib/di/injection.dart` | Nom de client envoyé à Jellyfin (`X-Emby-Authorization`) = « OB Max ». |
| `packages/server_core/lib/src/network/server_user_agent.dart` | User-agent `OBMax/<version>` dans les logs serveur. |
| `lib/data/services/push_messaging_service.dart` | Push Firebase désactivé (`ObMaxFeatures.pushMessaging`). |
| `lib/data/services/certificate_upload_server.dart` | Page d'envoi du `.p12` depuis le téléphone : version OB Max en français. |
| `lib/l10n/app_fr.arb`, `app_en.arb`, `app_en_GB.arb` | « Moonfin » → « OB Max » dans les textes visibles (sauf URL et chemins `Téléchargements/Moonfin`, qui désignent un vrai dossier). |
| `lib/l10n/app_localizations*.dart` | Générés depuis les `.arb`. Ne jamais les fusionner à la main : régénérer. |
| `lib/main.dart` | `ObMaxBoot.showSplash()` juste après l'init du binding, et `ObMaxBoot.finish(app)` à la place du `runApp` final : le splash animé tourne pendant toute l'initialisation. |
| `lib/ui/screens/auth/startup_screen.dart` | Affiche la dernière image du splash pendant la restauration de session ; passe toujours par la porte OB Max (jamais par l'écran utilisateurs d'un serveur mémorisé). |
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
| `ios/Runner/Assets.xcassets/AppIcon.appiconset/*.png` | Icône OB Max (générée depuis `obmax_ipad_1024.png`, sans canal alpha). |

## Ressources ajoutées (pas de conflit possible)

- `android/app/src/mobile/res/`, `android/app/src/androidTv/res/` : icônes OB Max (mipmaps, adaptive icon sur fond `#080A23`). Elles remplacent celles de `main/res` pour les flavors `mobile` et `androidTv`. La bannière TV est copiée sous le nom upstream `drawable-nodpi/moonfin_tv_banner.png` : le manifest (`android:banner="@drawable/moonfin_tv_banner"`) reste inchangé.
- Le splash natif Android 12+ (`values-v31/styles.xml`) utilise déjà `@color/ic_launcher_background` et `@mipmap/ic_launcher_foreground` : il passe automatiquement à `#080A23` + icône OB Max, sans modifier les styles.
