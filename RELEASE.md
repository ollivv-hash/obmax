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
