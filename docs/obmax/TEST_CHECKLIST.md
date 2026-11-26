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

## 2.2 — Son au démarrage

Spec : `docs/obmax/SON_SPLASH_SPEC.md`. Lecture par `audioplayers` (flux média, sans focus audio sur Android, catégorie `ambient` sur iOS). Pas de son sur Linux, le web ni l'Apple TV.

| # | Test | Android tél. | Shield | Box 32 bits | Windows | Mac | Comment vérifier |
|---|---|---|---|---|---|---|---|
| J1 | Démarrage à froid : son synchronisé | ☐ | ☐ | ☐ | ☐ | ☐ | « ah » à l'allumage de l'étoile, « aaahhh » + impact à l'arrivée de OB / MAX. Tuer l'app (pas seulement la quitter) avant chaque essai. |
| J2 | Retour depuis l'arrière-plan : pas de son | ☐ | ☐ | ☐ | ☐ | ☐ | Accueil, bouton Home, rouvrir OB Max depuis les apps récentes. |
| J3 | Splash passé par une touche / un tap : fondu puis silence | ☐ | ☐ | ☐ | ☐ | ☐ | Appuyer pendant l'animation, une fois l'app prête (deuxième lancement) : le son s'éteint en 150 ms, sans clic. |
| J4 | Réglage désactivé : aucun son | ☐ | ☐ | ☐ | ☐ | ☐ | *Personnalisation > Son au démarrage* désactivé, tuer puis relancer. |
| J5 | Téléphone en silencieux / vibreur : aucun son | ☐ | — | — | — | — | Tester les deux modes. |
| J6 | Musique en cours dans une autre app : pas coupée | ☐ | — | — | — | — | Lancer Spotify/Deezer puis OB Max : la musique continue (aucun focus audio demandé, elle n'est même pas baissée). |
| J7 | Box lente : pas de décalage audible, splash jamais bloqué | — | — | ☐ | — | — | Si le son n'est pas prêt en 300 ms, le splash part sans son : c'est voulu. `adb logcat \| grep "OB Max splash sound"` donne la raison. |
| J8 | Build release : contrôle ABI de `release.ps1` OK, taille APK notée | ☐ | ☐ | ☐ | — | — | Comparer avec la 2.0.5 : ________ Ko de plus (attendu : moins de 100 Ko). |

## En cas d'échec

Voir les commandes `logcat` de `SPIKE_REPORT.md` §4. Côté serveur, une ligne Caddy `TLS handshake error … client didn't provide a certificate` signe un problème de certificat.
