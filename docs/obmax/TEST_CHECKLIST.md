# OB Max v1 — recette

**Résultat (18/10/2026) : recette complète validée**, R1 à R14 sur le téléphone (en 4G) et sur la Shield, en build release signé : v1.0.0, puis v1.0.1 installée par l'OTA (R12). La v1.0.1 a aussi validé le nouvel écran de chargement et l'administration sur la Shield (R13).

Conditions : **build release signé** (voir `RELEASE.md`, dans ce dossier), téléphone **en 4G** (Wi-Fi coupé), Shield sur le réseau maison. Avant chaque série sur un appareil branché : `adb -s <device> logcat -c`.

Pour une install neuve, désinstaller d'abord toute version précédente d'OB Max.

| # | Test | Mobile | Shield | Comment vérifier |
|---|---|---|---|---|
| R1 | Install neuve : splash animé, puis écran certificat (pas de sélection de serveur) | ✅ | ✅ | Fond, étoile qui rebondit, allumage horaire depuis la pointe, halo doré, OB puis MAX, reflet sur le texte. Puis « Installer votre certificat », sans aucune saisie d'URL. |
| R2 | Import `.p12` (fichier sur mobile, QR sur TV), puis login / Quick Connect | ✅ | ✅ | Mobile : mauvais mot de passe → message clair, bon mot de passe → « Connexion au serveur… » puis utilisateurs. TV : QR + URL LAN, page d'envoi en français sur le téléphone. Tester aussi un fichier non `.p12`. |
| R3 | Thème OB Max partout, aucune mention « Moonfin » hors *À propos > Licences*, tout en français | ✅ | ✅ | Fond bleu nuit, focus or sur les vignettes, bouton « Lire » or, logo OB Max en haut à gauche. Téléphone réglé en anglais : l'app reste en français. |
| R4 | Accueil : ordre des sections conforme, media bar avec bandes-annonces | ✅ | ✅ | Media bar plein écran, puis Mes médias, Continuer de regarder, À suivre, Ajouts récents Films / Séries / Concerts (ordre des bibliothèques du serveur). |
| R5 | Livres, Musique, Live TV, jeux, Seerr, Cast, lecteur externe, multi-serveur absents | ✅ | ✅ | Navigation, Mes médias, fiche (pas de bouton Cast), lecteur (pas de bouton Cast), menu utilisateur (pas de « Sélectionner un serveur »). |
| R6 | Réglages : uniquement les éléments du §8.3 | ✅ | ✅ | Compte et sécurité, Lecture, Personnalisation, À propos (+ Administration pour un admin). Pas de barre de recherche. |
| R7 | Lecture direct play, 4K DV sur la Shield, **fluide en release** | ✅ | ✅ | Même film que le spike (Avatar 2, DV P7) : pas de saccades. |
| R8 | Sous-titres externes, changement de piste audio, seek, reprise | ✅ | ✅ | Quitter puis revenir : la reprise propose la bonne position. |
| R9 | Contrôle à distance depuis le web Jellyfin (WebSocket) | ✅ | ✅ | « Lire sur » l'appareil, pause / lecture / arrêt depuis le web. |
| R10 | Redémarrage de l'appareil : reconnexion sans réimporter le certificat | ✅ | ✅ | Redémarrer, lancer OB Max : splash puis accueil directement. |
| R11 | Téléchargement d'un épisode, app tuée puis relancée | ✅ | — | Le téléchargement reprend ou se termine ; lecture hors ligne possible. |
| R12 | OTA : publication d'une 1.0.1 de test, détection, téléchargement, vérification SHA, installation, données conservées | ✅ | ✅ | *À propos > Rechercher une mise à jour* : dialog en français, barre de progression, demande d'autorisation « sources inconnues » la première fois, installation, puis toujours connecté. |
| R13 | Admin Jellyfin : panneau admin visible ; compte non admin : masqué | ✅ | ✅ | *Réglages > Administration* pour un admin, absent pour les autres. Sur la Shield, les écrans ne sont pas adaptés à la télécommande : vérifier qu'on peut au moins naviguer et revenir. |
| R14 | Dashboard Jellyfin : le client apparaît comme « OB Max » | ✅ | ✅ | Tableau de bord > Appareils / Activité. |

## En cas d'échec

Voir les commandes `logcat` de `SPIKE_REPORT.md` §4. Côté serveur, une ligne Caddy `TLS handshake error … client didn't provide a certificate` signe un problème de certificat.

# OB Max 2.1.0 — recette (rattrapage Moonfin 3.0.0)

À faire en **build release signé** (`tools/release.ps1 -Version 2.1.0 -NoPublish -MacOS -Windows`, depuis la branche `sync/upstream-3.0.0`). Avant de commencer, mettre à jour le plugin **Moonbase en 3.0.0** sur Jellyfin : Moonfin 3.0 le recommande, mais l'app ne l'exige pas. Détail du rattrapage : [`SYNC_REPORT_3.0.0.md`](SYNC_REPORT_3.0.0.md).

**S2 est bloquant** : aucune publication tant qu'il n'est pas validé sur toutes les plateformes.

| # | Test | Android tél. | Shield | Box 32 bits | Windows | Mac | Notes |
|---|---|---|---|---|---|---|---|
| S1 | Build OK, contrôle ABI de `release.ps1` passé, signature avec lignage vérifiée | ☐ | ☐ | ☐ | ☐ | ☐ | Récapitulatif de `release.ps1` : deux ABI par APK, aucune `.so` présente pour une seule ABI. |
| S2 | **Mise à jour OTA depuis la 2.0.5** : certificat conservé, session conservée, pas de réactivation | ☐ | ☐ | ☐ | ☐ | ☐ | Le stockage des certificats est le même qu'en 2.0.5 (même fichier, mêmes clés). |
| S3 | Installation neuve : activation par code, puis login | ☐ | ☐ | — | ☐ | ☐ | |
| S4 | Lecture direct play, seek, reprise, sous-titres externes, pistes audio | ☐ | ☐ | ☐ | ☐ | ☐ | Windows : Moonfin 3.0 lit désormais dans la fenêtre native de mpv par défaut. |
| S5 | 4K Dolby Vision fluide | — | ☐ | — | — | — | |
| S6 | Lecture à distance (4G / hors LAN) sans coupure « Chargement… » | ☐ | — | — | ☐ | ☐ | |
| S7 | Contrôle à distance depuis le web Jellyfin (WebSocket) | ☐ | ☐ | ☐ | ☐ | ☐ | |
| S8 | Seerr : demande depuis un compte non admin | ☐ | ☐ | — | ☐ | ☐ | Statut « En attente » et notification Discord. |
| S9 | Interface 100 % en français, aucune mention « Moonfin » hors Licences, fonctions masquées toujours absentes | ☐ | ☐ | ☐ | ☐ | ☐ | Absents : musique, livres, Live TV, jeux, RomM, Cast, lecteur externe, Plex, ajout de serveur. |
| S10 | Nouveautés upstream classées « Garder » : fonctionnent avec le mTLS | ☐ | ☐ | ☐ | ☐ | ☐ | Lecteur : bouton Épisodes, décalages audio et sous-titres, deux sous-titres, nouvel écran Infos de lecture. Mini-lecteur (Mac, Windows). PIN synchronisé, QR Quick Connect. |
| S11 | Panneau admin : visible pour un admin, masqué sinon | ☐ | ☐ | — | ☐ | ☐ | Panneau refait par Moonfin 3.0. |
| S12 | Mac : mpv par défaut, choix utilisateur conservé | — | — | — | — | ☐ | Jamais touché → mpv ; désactivé à la main en 2.0.5 → reste désactivé. |
| S13 | Dashboard Jellyfin : le client apparaît comme « OB Max », version 2.1.0 | ☐ | ☐ | ☐ | ☐ | ☐ | |
