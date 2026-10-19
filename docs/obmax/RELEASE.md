# Publier une version d'OB Max

Les APK et `version.json` sont publiés en GitHub Releases sur le dépôt **public** `ollivv-hash/obmax-releases`. Le code source reste dans le dépôt privé `ollivv-hash/obmax`. L'app vérifie `https://github.com/ollivv-hash/obmax-releases/releases/latest/download/version.json` au démarrage (une fois par 24 h) et depuis *Réglages > À propos*.

## Une seule fois : la clé de signature

Toutes les versions doivent être signées avec **la même clé**. Sinon Android refuse la mise à jour et il faudrait désinstaller, ce qui efface les données et le certificat.

1. Créer le keystore **hors du dépôt** (exemple : `E:\obmax-keys\`) :

   ```powershell
   & "E:\jdk17\jdk-17.0.20.1+1\bin\keytool.exe" -genkeypair -v -storetype PKCS12 -keystore E:\obmax-keys\obmax-release.p12 -alias obmax -keyalg RSA -keysize 4096 -validity 36500 -dname "CN=OB Max, O=OB Max, C=FR"
   ```

2. Créer `android\keystore.properties` (ignoré par git). Pour y écrire le mot de passe sans le taper dans un éditeur, lancer `.\tools\set_keystore_password.ps1` : saisie masquée, vérification sur le keystore, puis écriture dans le fichier. Contenu attendu :

   ```properties
   storeFile=E:/obmax-keys/obmax-release.p12
   storeType=PKCS12
   storePassword=<mot de passe>
   keyAlias=obmax
   keyPassword=<mot de passe>
   ```

3. Sauvegarder le keystore et ses mots de passe ailleurs (gestionnaire de mots de passe, clé USB). **Sans lui, plus aucune mise à jour OTA n'est possible.**

## Changement de clé de signature (rotation)

Depuis la 2.0.1, OB Max est signé avec la clé enregistrée dans l'Android Developer Console (`D:\secrets\obmax-release.jks`, empreinte `26:58:2F:…:71:D2`). Les versions 1.0.0 à 2.0.0 étaient signées avec `E:\obmax-keys\obmax-release.p12` (`B4:6E:F4:…:8D:0C`).

Pour que les appareils déjà installés acceptent la mise à jour sans désinstaller, on utilise la rotation de clé d'Android (APK Signature Scheme v3) :

1. `.\tools\rotate_signing_key.ps1` (une seule fois) : demande le mot de passe du nouveau keystore, vérifie les deux empreintes, crée la lignée `D:\secrets\obmax-rotation.lineage` (l'ancienne clé « signe » la nouvelle) et réécrit `android\keystore.properties` (nouvelle clé + `previous*` + `lineageFile`). L'ancien fichier est copié dans `E:\obmax-keys\keystore.properties.avant-rotation`. Relancé plus tard, le script ne fait que vérifier.
2. `release.ps1` détecte la rotation : après le build Gradle, il re-signe chaque APK avec `apksigner` (ancienne clé en v2 pour Android 7 à 8.1, nouvelle clé + lignée en v3 pour Android 9 et plus), puis vérifie les deux empreintes.

**À conserver pour toujours, ensemble** : les deux keystores, leurs mots de passe et le fichier `.lineage`. Un APK construit sans `release.ps1` (Gradle seul) n'est signé qu'avec la nouvelle clé : il ne peut pas mettre à jour une installation antérieure à la 2.0.1.

## Une seule fois : la CLI GitHub

```powershell
winget install GitHub.cli
gh auth login
```

## À chaque version

```powershell
.\tools\release.ps1 -Version 1.0.1 -Notes "Corrections et améliorations."
```

Le script :

1. passe `pubspec.yaml` à `1.0.1+<versionCode précédent + 1>` (le `versionCode` est commun aux deux flavors, c'est lui que l'OTA compare) ;
2. construit les APK release signés `mobile` et `androidTv` (arm64 ; ajouter `-Armv7` pour inclure aussi l'ARM 32 bits dans les mêmes APK) ;
3. copie `obmax-mobile-1.0.1.apk`, `obmax-tv-1.0.1.apk` et `version.json` (avec les SHA-256) dans `dist\v1.0.1\` ;
4. affiche le récapitulatif et **demande confirmation** avant `gh release create v1.0.1 … --repo ollivv-hash/obmax-releases`.

Options : `-NoPublish` (build, empreintes et `version.json` seulement, `pubspec.yaml` restauré), `-VersionCode N` (forcer le versionCode, par exemple `1` pour la toute première release), `-Yes` (publier sans la question de confirmation, le récapitulatif reste affiché), `-Mandatory` (pas de bouton « Plus tard »), `-ReleasesRepo` (autre dépôt), `-AllowDebugSigning` (build de test uniquement, jamais publié).

**Versions Mac et Windows (`-MacOS`, `-Windows`).** Le `.dmg` se construit sur un Mac de GitHub Actions (workflow `.github/workflows/obmax-macos.yml`, signature ad hoc, sans compte Apple) et l'installateur Windows sur une machine Windows (`obmax-windows.yml`, x64, non signé : SmartScreen avertit au premier lancement). Avec `-MacOS` et/ou `-Windows`, `release.ps1` lance ces builds au début, à partir du code **poussé** (il refuse si `obmax/main` n'est pas à jour sur GitHub), construit les APK pendant ce temps, attend le `.dmg` et l'installateur (20 à 45 min), les télécharge dans `dist\v<version>\` et les publie avec les APK. `version.json` les liste sous `assets.macos` et `assets.windows`. Sur Mac et Windows, l'app vérifie la dernière release et propose la nouvelle version (sur Windows, elle télécharge et lance l'installateur).

Après publication, commiter le changement de version :

```powershell
git commit -am "release: OB Max 1.0.1"
```

## Première installation (sideload)

- **Téléphone** : ouvrir le lien de l'APK `obmax-mobile-…` sur le téléphone et autoriser l'installation depuis le navigateur.
- **Shield** : `adb connect <ip>:5555` puis `adb install obmax-tv-1.0.1.apk`, ou une app comme *Downloader*.

Les mises à jour suivantes arrivent par l'OTA. Au premier « Mettre à jour », Android demande d'autoriser OB Max à installer des applications.

## Dépannage

- Le `version.json` doit être un asset de la **dernière** release (pas une pre-release ni un brouillon), sinon l'URL `latest/download` ne le trouve pas.
- « Empreinte SHA-256 invalide » : l'APK a été remplacé sur la release après génération du `version.json`. Republier les trois fichiers ensemble.
- Une installation refusée (« conflit avec un paquet existant ») vient presque toujours d'une signature différente.
