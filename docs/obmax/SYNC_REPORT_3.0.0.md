# Synchronisation avec Moonfin 3.0.0

Rapport du rattrapage d'OB Max 2.0.5 sur Moonfin 3.0.0, pour la version OB Max 2.1.0. Spécification : `OBMAX_2.1.0_SPEC.md` (hors dépôt). Procédure générale : [`OBMAX_CHANGES.md`](../../OBMAX_CHANGES.md).

## 1. Tag et méthode

| | |
|---|---|
| Tag upstream | **3.0.0** (30/10/2026), dernière version stable, marquée « Latest ». Identique à 2.8.0 (29/10) au numéro de version près. |
| Base précédente d'OB Max | `a279489fb` (16/10/2026), entre les tags 2.7.0 et 2.8.0 |
| Retard rattrapé | 484 commits upstream ; 964 fichiers modifiés upstream |
| Commits OB Max conservés | 67, inchangés |
| Méthode | **merge** de `3.0.0` dans `sync/upstream-3.0.0` (créée depuis `obmax/main`), validée le 03/11/2026. Pas de rebase, pas de force-push. |
| Sauvegarde | tag `backup/2.0.5-pre-sync` sur `a1bfc8363`, poussé sur `origin` |
| Non retenu | `upstream/main`, déjà 326 commits après 3.0.0 mais non publié en version stable |

## 2. Conflits et résolution

11 fichiers en conflit, plus les 56 fichiers de traduction générés.

| Fichier | Résolution |
|---|---|
| `lib/auth/store/client_certificate_store_io.dart` | **Version upstream**, conformément à la spec : notre PR #1930 y est fusionnée à l'identique. Notre commentaire `// OBMAX:` disparaît. |
| `lib/ui/screens/auth/server_select_screen.dart` | **Version upstream** : la boîte « Ajouter un serveur », où vivait notre correctif #1894, a été déplacée dans `add_server_dialog.dart` et refaite. L'écran reste masqué par la porte OB Max. |
| `lib/di/modules/playback_module.dart` | Upstream : nouveau lecteur Apple natif (tvOS, iOS) à côté d'Aether. OB Max : `ObMaxMacPlayer.usesAether` remplace `isIOS \|\| isMacOS` à l'enregistrement, au backend initial et dans le sélecteur ; le lecteur natif reste réservé à iOS et tvOS. |
| `lib/ui/screens/playback/video_player_screen.dart` | Surface vidéo : `ObMaxMacPlayer.usesAether \|\| isAppleTV` à la place de `isApple \|\| isAppleTV`. Sur Mac avec mpv, la surface mpv est utilisée. |
| `lib/ui/navigation/app_router.dart` | Upstream ouvre l'administration à Emby (`adminServerSupported()`). OB Max garde l'accès sur TV : `(!isTV \|\| ObMaxFeatures.adminOnTv) && adminServerSupported()`. Imports OB Max conservés. |
| `lib/ui/screens/home/home_screen.dart` | Upstream ajoute les styles d'arrière-plan « Coin » et « Haut ». Le voile OB Max (`ObMaxBackdropVeil`) enveloppe désormais le `FullscreenBackdropSwitcher`, avant ces styles. |
| `lib/di/modules/app_module.dart`, `lib/ui/screens/detail/detail_buttons.dart` | Imports : les deux conservés. |
| `pubspec.yaml` | Version OB Max (`2.0.5+8`) et assets OB Max conservés ; nouveaux assets upstream (`assets/reader/`, polices Literata, icônes sociales) ajoutés. |
| `lib/l10n/app_en.arb`, `app_en_GB.arb`, `app_fr.arb` | Fusion clé par clé : texte upstream de départ (doublons et échappements compris), puis nos changements réappliqués (44 « Moonfin » → « OB Max » en anglais, 43 en anglais britannique, 46 en français). 149 traductions françaises que nous avions ajoutées sont désormais livrées par Moonfin : **leur formulation est retenue**, sauf `playbackVideoUnsupported` (la leur propose un lecteur externe, absent d'OB Max). |
| `lib/l10n/app_localizations*.dart` | Version upstream, puis régénération par `flutter gen-l10n`. |

Fichiers modifiés des deux côtés et fusionnés sans conflit (vérifiés) : `MainActivity.kt` (enregistrement de l'installateur OTA intact), `AndroidManifest.xml` (permission `REQUEST_INSTALL_PACKAGES` intacte), `lib/app.dart`, `lib/main.dart`, `lib/playback/media_kit_player_backend.dart` (décodage matériel forcé sur Mac avec mpv), `lib/preference/preference_constants.dart`, `lib/ui/screens/auth/server_screen.dart`, `lib/ui/screens/detail/item_detail_screen.dart`, `lib/ui/screens/settings/settings_side_panel.dart`, `lib/ui/widgets/top_toolbar.dart`, `lib/ui/widgets/user_menu_dialog.dart`.

### Correctifs déjà fusionnés upstream

Les fichiers de nos PR **#1893** (WebSocket mTLS), **#1894** (import du certificat sur l'hôte joint) et **#1930** (trousseau macOS) sont maintenant **identiques à Moonfin 3.0.0**, tests compris : `client_certificates_io.dart`, `server_select_screen.dart`, `server_repository.dart`, `server_addition_state.dart`, `client_certificate_store_io.dart`, `test/auth/server_repository_client_cert_test.dart`, `test/auth/client_certificate_store_io_test.dart`. Plus aucun doublon.

## 3. Zones sensibles (spec §2.3)

| # | Zone | Constat |
|---|---|---|
| 1 | Stockage sécurisé | **Aucun changement** : `flutter_secure_storage` reste en `^10.0.0` (10.3.4 résolu), mêmes options, mêmes clés (`mtls_client_cert_hosts`, préfixe des certificats). Le seul fichier concerné est notre propre PR #1930. Voir §7 pour l'avertissement « bad base-64 ». |
| 2 | Certificats client / mTLS | `client_certificates_io.dart` identique au nôtre. `configure_server_dio_io.dart` réorganisé (option `limitRequests`) sans toucher au certificat. `mpv_client_certificate.dart`, `mpv_ca_bundle.dart`, Media3 : pas de changement upstream sur le certificat. Côté Apple, `ClientIdentityStore.swift` et `EngineTrustPolicy.swift` évoluent avec Aether : sur Mac ils ne servent que si mpv est désactivé. |
| 3 | Mises à jour (OTA) | `app_update_service.dart` inchangé upstream. `ObMaxInstaller` et la permission d'installation sont intacts. |
| 4 | Flutter, Gradle, AGP, SDK, NDK | **Aucun changement** : Flutter 3.47.2 côté upstream (OB Max compile en 3.47.7), mêmes contraintes `sdk`/`flutter`, aucun fichier Gradle modifié. `release.ps1`, la signature avec lignage et le contrôle ABI ne sont pas concernés. |
| 5 | Schéma de stockage | Base hors ligne toujours en version 2. Le changement de dossier de la base ne concerne que le Flatpak Linux. |
| 6 | Refonte touchant un point d'accroche | Écran d'ajout de serveur refait (hors de portée d'OB Max) ; réglages réorganisés (le panneau OB Max les remplace toujours) ; administration ouverte à Emby (point d'accroche adapté). Tous les points d'accroche sont toujours présents : `git grep OBMAX` en trouve autant qu'avant, moins celui du stockage des certificats. |
| 7 | Nouvelles dépendances | Aucune dépendance externe. Paquets internes `server_plex` et `playback_plex` (Plex, masqué). `liquid_glass_widgets` 1.4.2 → 1.6.0 (interface). Fork media_kit de Moonfin : correctif Linux uniquement. Apple : AetherEngine et FFmpegBuild 3.10.1. |

## 4. Nouveautés visibles et classement (spec §2.4)

### Garder

| Nouveauté | Remarque |
|---|---|
| Lecteur : bouton Épisodes, réglage des décalages audio et sous-titres, deux sous-titres simultanés, maintien pour lire en ×2 (mobile), clic pour pause (ordinateur), raccourcis clavier, nouvel écran Infos de lecture | Tout passe par le lecteur et le serveur. |
| Mini-lecteur sur ordinateur (Mac, Windows) | Sur Mac avec mpv, le mini-lecteur utilise la surface mpv (point d'accroche existant). |
| Windows : lecture dans la fenêtre native de mpv par défaut (réglage « Video Renderer ») | Mêmes propriétés mpv, donc même certificat ; à vérifier en recette (S4). |
| Réglage « Sous-titres secondaires » dans *Lecture > Sous-titres* | Écran déjà ouvert par le panneau OB Max. |
| Arrière-plan de la fiche (taille, plein écran), sous-titres des bandes-annonces | *Personnalisation > Fiche détaillée*. |
| Affiches des rangées « Modernes » (TV, ordinateur) deux fois moins hautes qu'en 2.0.5 : elles suivent désormais la « Taille des visuels » comme les rangées classiques | Décision du 05/11/2026 : nouvel écran *Personnalisation > Affichage* (taille des visuels, type et espacement des rangées, rangées étendues, visuel de la série, description ; sur TV et ordinateur, taille de l'interface et animations), pour que chacun règle la taille. Pas de thèmes, d'édition des rangées ni de sources externes. |
| Choix de bandes-annonces avec vignettes YouTube (`i.ytimg.com`) | OB Max lit déjà les bandes-annonces YouTube dans la bannière : même service tiers. |
| Section « Services de streaming » (via Seerr) | Passe par le plugin, sur le serveur. |
| Code PIN synchronisé par le plugin Moonbase | Passe par le serveur ; copie locale si le serveur ne répond pas. |
| QR code Quick Connect, horaires d'accès appliqués (écran « Temps écoulé ») | Décidés par le serveur Jellyfin. |
| Styles de clavier sur TV (par défaut « Ancré »), styles de bibliothèque, barre de recherche | Interface. |
| Panneau d'administration refait | Toujours réservé aux administrateurs, sur TV compris. |
| « Lire depuis le serveur » pour les téléchargements | Passe par le serveur. |
| Effets saisonniers (objet qui suit la sélection, activé par défaut pendant les fêtes) | Purement visuel. |

### Masquer

| Nouveauté | Comment |
|---|---|
| Connexion Plex (`/plex-sign-in`) | Route bloquée (`ObMaxFeatures.plex = false`). L'ajout de serveur reste hors de portée. |
| Compte RomM (`/romm-account`) | Route bloquée (bibliothèques de jeux déjà masquées). |
| Musique, livres (nouvelles pages de catégories `/music/…`, `/books/…`), Live TV (retour en arrière, enregistrements), jeux | Déjà masqués : préfixes de routes et filtre des bibliothèques. |
| Listes externes IMDb/TMDB dans la bannière | Désactivées par défaut (`mediaBarExternalLists` vide) et leur réglage n'est pas dans le panneau OB Max. |
| Pages d'administration propres à Emby | Affichées seulement sur un serveur Emby. |
| Liens des personnes (IMDb, TMDB, réseaux sociaux, site officiel) | Décision du 04/11/2026 : non proposés. `ObMaxFeatures.hiddenDetailSections`, appliqué dans `DetailSection.isOffered` (pas de réglage, pas d'appel au plugin) et dans `DetailSectionVisibility.shows` (aucun style de fiche ne les affiche). |
| Critiques TMDB et lien « Lire sur TMDB » | Idem, décision du 04/11/2026. |
| Assistant de premier lancement (nouvelles étapes) | Toujours désactivé. |

### À arbitrer

Aucun point restant. Les liens des personnes et les critiques TMDB, soumis à arbitrage, sont masqués (tableau ci-dessus) : ils ouvraient des sites tiers dans le navigateur.

## 5. Points d'accroche

- **Retiré** : `lib/auth/store/client_certificate_store_io.dart` (PR #1930 fusionnée).
- **Adaptés** : choix du backend et surface vidéo (`ObMaxMacPlayer.usesAether`), garde de l'administration (`adminServerSupported()`), voile de l'accueil (autour du `FullscreenBackdropSwitcher`).
- **Ajoutés** : `ObMaxFeatures.plex` et les routes `/plex-sign-in`, `/romm-account` dans `lib/obmax/obmax_features.dart` (code OB Max, sans nouveau point d'accroche) ; `lib/preference/detail_section_layout.dart`, deux points d'accroche (`isOffered`, `shows`) pour `ObMaxFeatures.hiddenDetailSections`.
- **Traductions** : 272 clés traduites en français (aucune clé manquante). Nouvelle mention « Moonfin » remplacée : `smartDownloadsEnableDescription`. Restent, comme avant : le dossier `Téléchargements/Moonfin` et l'URL du code source. Aucun nouveau « Moonfin » écrit en dur dans le code Dart visible.

## 6. Vérifications

- `flutter analyze lib test` : **0 erreur** (12 avertissements, tous dans du code Moonfin).
- Les erreurs de `flutter analyze` à la racine viennent des tests internes des paquets de Moonfin (`packages/*/test`), qui ont besoin de leurs propres dépendances : sans rapport avec OB Max.
- `flutter test` : **5 706 tests réussis, 5 échecs attendus** : un test du bouton Cast (masqué par OB Max) et quatre de l'écran de chargement de Moonfin (OB Max affiche « Chargement… » avec son logo au lieu de « LOADING STREAM… »). Ces écarts viennent de choix OB Max antérieurs, pas du rattrapage.
- `mpv par défaut sur Mac` (commit `a1bfc8363`) : déjà sur la branche, puisqu'elle part d'`obmax/main`. La préférence garde la même clé (`obmax_macos_mpv_player`) avec `true` par défaut : jamais touchée → mpv ; désactivée à la main → reste désactivée.

## 7. Points à valider

1. **Tag 3.0.0 et merge** : validés le 03/11/2026.
2. **Liens des personnes et critiques TMDB** : masqués (décision du 04/11/2026).
3. **Plugin Moonbase** : passer de 2.4.0 à 3.0.0 sur Jellyfin avant la recette. Moonfin le recommande ; l'app n'exige aucune version minimale et l'accès à Seerr n'a pas changé.
4. **Avertissement « FlutterSecureStorage bad base-64 »** : **non lié au rattrapage** (bibliothèque et options inchangées). Il vient du décodage d'une valeur stockée sur Android. Point d'attention : `flutter_secure_storage` 10 active `resetOnError` par défaut. Une valeur illisible fait alors effacer la clé concernée, voire **tout le stockage** lors d'une lecture globale (`readAll`), certificat compris, ce qui obligerait l'appareil à se réactiver. C'est le comportement de la 2.0.5 comme de la 3.0.0. Une correction (par exemple `resetOnError: false` pour le stockage des certificats) touche le stockage sécurisé : **reportée à la 2.2** (décision du 04/11/2026).
