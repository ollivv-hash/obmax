# OB Max — Son au démarrage (spec)

Version cible : **2.2**. Destinataire : Claude Code.

## 0. Principes (rappel)

- Diff minimal avec Moonfin. Code dans `lib/obmax/splash/` ; points d'accroche upstream marqués `// OBMAX:` et listés dans `OBMAX_CHANGES.md`.
- Aucune identité de l'administrateur dans le dépôt public.
- **Toute nouvelle dépendance doit être validée par moi avant d'être ajoutée** (voir §3).

## 1. Objectif

Jouer un court jingle synchronisé avec l'animation du splash `ObMaxSplash` (2 600 ms), à chaque démarrage à froid, sur toutes les plateformes (Android téléphone, Android TV, Windows, Mac).

## 2. Asset

| Fichier | Format | Taille | Usage |
|---|---|---|---|
| `assets/obmax/splash/obmax_splash.m4a` | AAC 128 kb/s, 48 kHz, 2,60 s, −16 LUFS | 32 Ko | **Fichier principal**, toutes plateformes |
| `assets/obmax/splash/obmax_splash.ogg` | Vorbis q5, mêmes caractéristiques | 21 Ko | Repli uniquement si une plateforme ne lit pas l'AAC avec la solution retenue |

- Le **calage est intégré au fichier** : 1er « ah » à 0,72 s (allumage de l'étoile), « aaahhh » + impact à 0,98 s (arrivée de OB / MAX), queue de réverbération jusqu'à 2,60 s.
- Donc : lancer la lecture **au même instant** que `AnimationController.forward()`, sans décalage.
- Déclarer l'asset dans `pubspec.yaml`.

## 3. Lecture audio — à me proposer avant de coder

1. Vérifier dans `pubspec.yaml` si une bibliothèque audio est **déjà présente** (`just_audio`, `audioplayers`, `media_kit`…) et utilisable pour un asset court sur les 4 plateformes. Si oui, la réutiliser.
2. Sinon, me proposer **une** dépendance (ex. `audioplayers`) avec : support des 4 plateformes, poids ajouté à l'APK, licence, impact sur `release.ps1` et sur le contrôle ABI (armv7 + arm64, pas de x86_64). **Attendre ma validation.**
3. Ne pas utiliser Media3 / mpv du lecteur vidéo pour ça, sauf si c'est la seule option sans dépendance et que tu me le proposes.

## 4. Comportement

- **Préchargement** : charger le son en même temps que les 5 images (`precacheImage`), avant de lancer le controller. Si le chargement échoue ou dépasse 300 ms, lancer l'animation **sans son** (jamais de blocage du splash).
- **Démarrage à froid uniquement** (pas au retour depuis l'arrière-plan).
- **Passage du splash** (touche télécommande / tap) : fondu de sortie de 150 ms puis arrêt.
- **Fin** : le son se termine seul à 2,6 s. Si l'init est plus longue, le halo continue de pulser **en silence** (pas de boucle).
- **Mobile Android** :
  - pas de son si le téléphone est en mode **silencieux ou vibreur** (`AudioManager.getRingerMode()` ≠ normal) ;
  - flux **média** (`USAGE_MEDIA` / `CONTENT_TYPE_SONIFICATION`) ;
  - **ne pas interrompre** la musique d'une autre app : pas de prise de focus permanente (au plus `AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK`, ou aucun focus).
- **Android TV, Windows, Mac** : son joué si le réglage est actif, au volume système.
- iOS : code compatible si la bibliothèque le permet, catégorie audio `ambient` (respecte le bouton silencieux) ; aucun build attendu.

## 5. Réglage

- *Personnalisation* : interrupteur **« Son au démarrage »**, activé par défaut sur toutes les plateformes.
- Clé `.arb` FR : `obmaxSplashSoundSetting` = « Son au démarrage », sous-titre « Jouer le jingle OB Max au lancement de l'application ».
- Passer par le mécanisme centralisé de réglages OB Max (`lib/obmax/`).

## 6. Recette

| # | Test | Android tél. | Shield | Box 32 bits | Windows | Mac |
|---|---|---|---|---|---|---|
| J1 | Démarrage à froid : son synchronisé (« ah » à l'étoile, « aaahhh » à OB/MAX) | ☐ | ☐ | ☐ | ☐ | ☐ |
| J2 | Retour depuis l'arrière-plan : pas de son | ☐ | ☐ | ☐ | ☐ | ☐ |
| J3 | Splash passé par une touche / un tap : fondu puis silence | ☐ | ☐ | ☐ | ☐ | ☐ |
| J4 | Réglage désactivé : aucun son | ☐ | ☐ | ☐ | ☐ | ☐ |
| J5 | Téléphone en silencieux / vibreur : aucun son | ☐ | — | — | — | — |
| J6 | Musique en cours dans une autre app : pas coupée (au pire baissée brièvement) | ☐ | — | — | — | — |
| J7 | Box lente : pas de décalage audible son/animation, splash jamais bloqué | — | — | ☐ | — | — |
| J8 | Build release : contrôle ABI de `release.ps1` toujours OK, taille APK notée | ☐ | ☐ | ☐ | — | — |

## 7. Livrables

1. Assets + code dans `lib/obmax/splash/`, réglage, clés `.arb` FR.
2. `OBMAX_CHANGES.md` et `TEST_CHECKLIST.md` à jour.
3. Résumé : solution audio retenue, poids ajouté, points à valider.
