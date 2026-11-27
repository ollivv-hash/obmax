# Synchronisation avec Moonfin 3.1.1

Rapport du rattrapage d'OB Max 2.2.1 sur Moonfin 3.1.1, pour la version OB Max 2.3.0. Même procédure que pour 3.0.0 ([`SYNC_REPORT_3.0.0.md`](SYNC_REPORT_3.0.0.md)) et [`OBMAX_CHANGES.md`](../../OBMAX_CHANGES.md).

## 1. Tag et méthode

| | |
|---|---|
| Tag upstream | **3.1.1** (18/11/2026), dernière version stable |
| Base précédente d'OB Max | 2.2.1, sur Moonfin d'avant 3.0.0 (la branche `sync/upstream-3.0.0` n'avait jamais été fusionnée) |
| Retard rattrapé | 3.0.0 (déjà résolu sur `sync/upstream-3.0.0`) puis 962 commits de 3.0.0 à 3.1.1 |
| Méthode | branche `sync/upstream-3.1.1` créée depuis `sync/upstream-3.0.0`, **merge** d'`obmax/main` (2.2.0 et 2.2.1 : son au démarrage), puis **merge** de `3.1.1`. Pas de rebase, pas de force-push. |
| Sauvegarde | tag `backup/2.2.1-pre-sync` sur `obmax/main` (`a14ece6bd`), poussé sur `origin` |
| Non retenu | `upstream/main`, 301 commits après 3.1.1, sans version stable |

## 2. Conflits et résolution

Merge d'`obmax/main` : `pubspec.yaml` (override `audioplayers_linux` du son ajouté à côté de la nouvelle révision de media-kit) et les traductions (clés des deux côtés gardées, fichiers générés recréés par `flutter gen-l10n`).

Merge de 3.1.1 :

| Fichier | Résolution |
|---|---|
| `android/app/build.gradle.kts` | **Un seul APK pour téléphones et TV** (Moonfin 3.1 a supprimé le flavor `androidTv` ; l'app choisit l'interface TV, le moteur de rendu et le Cast au lancement). L'identifiant d'application privé reste, la liste `abis` d'upstream perd `x86_64`. Le dossier `android/app/src/androidTv/res/` (icônes, bannière, identiques à celles de `mobile`) est retiré. |
| `pubspec.yaml` | Version OB Max gardée ; `android_tv_version` / `android_tv_build_number` disparaissent avec le flavor TV. Assets du splash gardés à côté des nouveaux (`assets/after_hours/`). |
| `lib/main.dart` | `MacosTouchInput.install()` puis `ObMaxBoot.showSplash()` ; `DeviceHinge.init()` puis `ObMaxBoot.finish(...)`. |
| `lib/data/services/push_messaging_service.dart` | Version upstream (Firebase ne démarre plus qu'à l'enregistrement) ; le garde `ObMaxFeatures.pushMessaging` passe en tête de `registerWithCurrentToken()` et de `unregister()`. |
| `lib/ui/screens/settings/settings_side_panel.dart` | **Version upstream** (le panneau est découpé en `part` dans `panel/`, avec onglets et aperçu en direct), puis nos accroches : imports OB Max, `part` du panneau OB Max, admin sur TV, recherche masquée, et `_buildCategories()` qui renvoie `_obMaxCategories()`. Notre panneau devient une liste de catégories (Compte et sécurité, Lecture, Demandes, Personnalisation, À propos, + Administration), aperçu coupé. |
| `lib/ui/screens/home/home_screen.dart` | Le fond de l'accueil est parti dans `home_backdrop.dart` : le voile bleu nuit (`ObMaxBackdropVeil`) y est reporté. |
| `lib/ui/screens/auth/server_screen.dart`, `lib/ui/widgets/user_menu_dialog.dart` | Versions upstream (écrans refaits), puis nos masquages : « Sélectionner un serveur » et « Déconnecter tous les utilisateurs ». |
| `lib/ui/widgets/top_toolbar.dart` | Logo OB Max gardé ; l'avatar passe par le nouveau `UserAvatarImage`. |
| `lib/playback/media_kit_player_backend.dart`, `lib/ui/screens/playback/osd_buttons.dart` | Imports des deux côtés. |
| `lib/l10n/*.arb` | Nouvelles clés gardées des deux côtés ; textes reformulés par upstream pris tels quels, « Moonfin » remplacé par « OB Max ». |

Corrections après le merge : `player_loading_overlay.dart` (variable renommée upstream), et le nouveau style de rangées « Carrousel » ajouté au choix de *Personnalisation > Affichage*.

## 3. Zones sensibles

| # | Zone | Constat |
|---|---|---|
| 1 | Stockage sécurisé | **Aucun changement upstream** (même bibliothèque, mêmes options, mêmes clés). OB Max passe `resetOnError: false` (validé le 27/11/2026, voir §7). |
| 2 | Certificats / mTLS | `client_certificates_io.dart` : le réglage « certificats auto-signés » ne vaut plus que pour les serveurs de l'utilisateur (`acceptsUntrustedCertificate`). Sans effet sur le certificat client. |
| 3 | OTA | Nos fichiers `lib/obmax/ota/` inchangés. **Un seul APK** : `release.ps1` le publie sous les clés `mobile` **et** `androidTv` de `version.json`, car les TV en 2.2.1 cherchent `androidTv` (valeur compilée `OBMAX_FLAVOR`). Le nouvel APK ne passe plus `OBMAX_FLAVOR` : l'app demande à l'appareil. |
| 4 | Toolchain | Flutter 3.47.2, compileSdk 36, NDK 28.2 : inchangés. Flavor TV supprimé (voir §2). |
| 5 | Schéma de stockage | Rien de notable. |
| 6 | Refontes touchant nos accroches | Panneau des réglages, fond de l'accueil, écran serveur, menu utilisateur, push : accroches reportées (§2, `OBMAX_CHANGES.md`). |
| 7 | Nouvelles dépendances | `server_silo`, `playback_silo` (paquets locaux, serveur Silo) ; `firebase_app_installations` (inerte : push coupé). |

## 4. Nouveautés visibles et classement

### Garder
- Rangées en **carrousel** avec panneau de détails (style par défaut sur TV chez Moonfin), choix ajouté dans *Personnalisation > Affichage*.
- **Calendrier** des sorties (agenda, compte à rebours, rappels).
- Nouveaux badges et étiquettes sur les affiches, media bar « Nouveautés ».
- Correctifs du lecteur mpv (pistes audio par fichier), image dans l'image, recadrage des bandes noires.
- **Watch parties** Moonbase (salons, invitations, chat, lecture synchronisée) : décision du 27/11/2026.
- **Lignes MDBList, JustWatch et TMDB Discover** : décision du 27/11/2026. Quatre lignes ajoutées aux rangées fixes de l'accueil, après les derniers ajouts : *Top films en streaming du jour* et *Top séries en streaming du jour* (JustWatch, pays de l'appareil), *Films les plus attendus* (MDBList), *Nouveautés en numérique* (TMDB). Titres traduits par OB Max. L'accueil n'affiche une ligne que si Moonbase peut la remplir (clé MDBList ou TMDB configurée dans le plugin).
- Seerr : suivi des téléchargements, « Obtenir une autre version », notification de test.

### Masquer (sans code ajouté)
- **Serveurs Silo** : on n'y accède que par « Sélectionner un serveur », déjà bloqué.
- **Mini-jeux After Hours** : ouverts par 7 appuis sur la version dans l'*À propos* de Moonfin, qu'OB Max remplace par le sien.
- Nouveautés **Live TV** (guide, favoris, raccourcis) : routes `/live-tv` déjà bloquées.

## 5. Langue et identité
- 57 nouvelles clés traduites en français, aucune manquante.
- 33 mentions « Moonfin » des textes français remplacées par « OB Max ». Restent, comme avant : le dossier `Téléchargements/Moonfin` et l'URL du code source.
- Notification de lecture à distance : titre de secours « OB Max ».
- Nom du client vu par Jellyfin (`kObMaxAppName`) et user-agent `OBMax/…` inchangés.

## 6. Vérifications
- `flutter analyze lib test/obmax` : **0 erreur** (avertissements dans du code Moonfin).
- `flutter test` : **7 320 tests réussis, 23 échecs attendus**, tous dus à des choix OB Max antérieurs (aucun à la fusion) : Cast masqué (3 tests qui cherchent le bouton Cast), écran de chargement OB Max au lieu de « LOADING STREAM… » (4 + 3 dans l'aperçu en direct), nom « OB Max » dans le titre d'onglet (4), liens des personnes et critiques TMDB masqués (9). Moonfin a ajouté des tests sur ces zones ; en 3.0.0, 5 échecs du même type.

## 7. Points à valider
1. **`resetOnError` du stockage sécurisé** : **validé et fait** (27/11/2026). `flutter_secure_storage` 10.3.4 a `resetOnError: true` par défaut : une lecture ratée efface l'entrée, et un `readAll` raté (utilisé pour lister les certificats) efface **tout** le stockage. Passé à `false` sur le store des certificats et sur celui des identifiants, qui partagent le même fichier. Seul le comportement en cas d'erreur change : ni l'emplacement ni le format du stockage. Une lecture ratée renvoie « rien » ; pour les certificats, `getAll()` se replie alors sur la lecture hôte par hôte.
2. **Lignes MDBList / JustWatch / TMDB** : **validé et fait** (27/11/2026), quatre lignes ajoutées aux rangées par défaut (§4). Vérifier dans Moonbase qu'une clé MDBList et une clé TMDB sont renseignées, sinon ces lignes restent absentes.
3. **Plugin Moonbase** : les watch parties passent par le plugin, et le calendrier par Seerr (un admin doit y être connecté). L'app n'exige aucune version minimale du plugin ; le mettre à jour sur Jellyfin avant la recette, comme pour 3.0.0.
4. **Numéro de version** : 2.3.0 proposé.

