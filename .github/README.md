<p align="center">
  <img src="../assets/obmax/logo.png" alt="OB Max" width="160">
</p>

<h1 align="center">OB Max</h1>
<p align="center"><b>Client Jellyfin privé, basé sur <a href="https://github.com/Moonfin-Client/Moonfin-Core">Moonfin</a></b></p>

---

OB Max est une version personnalisée de Moonfin pour un seul serveur Jellyfin privé. L'accès se fait **sur invitation** : chaque appareil s'active avec un code à usage unique et reçoit son propre certificat client. Le serveur exige ce certificat (TLS mutuel), si bien que sans lui, rien n'est accessible.

Ce n'est donc **pas** un client Jellyfin générique. Pour votre propre serveur, utilisez [Moonfin](https://github.com/Moonfin-Client/Moonfin-Core).

## Installer

Les versions publiées sont sur **[ollivv-hash/obmax-releases](https://github.com/ollivv-hash/obmax-releases/releases/latest)** :

| Appareil | Fichier |
|---|---|
| Téléphone ou tablette Android | `obmax-mobile-x.y.z.apk` |
| Android TV, Google TV, Nvidia Shield | `obmax-tv-x.y.z.apk` |
| Mac (macOS 15 ou plus récent) | `obmax-macos-x.y.z.dmg` |
| PC Windows 10 ou 11 (x64) | `obmax-windows-x.y.z.exe` |

Le pas-à-pas pour les invités (téléphone, TV, navigateur web) se trouve dans [`docs/obmax/guide-installation.html`](../docs/obmax/guide-installation.html) : téléchargez le fichier, puis ouvrez-le dans un navigateur. Les mises à jour arrivent ensuite directement dans l'app.

## Ce qu'OB Max change par rapport à Moonfin

- **Un seul serveur**, fixé à la compilation : pas d'ajout de serveur, pas d'Emby.
- **Activation par code d'invitation** : l'appareil crée sa clé, obtient un certificat valable 180 jours et le renouvelle tout seul. Une page d'administration sert à inviter et révoquer les appareils.
- **Interface allégée** : pas de musique, de livres, de Live TV, de jeux, de Seerr, de Cast ni de lecteur externe ; réglages réduits à l'essentiel.
- **Identité OB Max** : nom, icônes, thème, écran de démarrage animé, interface en français.
- **Mises à jour intégrées** : sur Android, l'APK s'installe depuis l'app ; sur Mac et Windows, l'app propose la nouvelle version.

## Organisation du dépôt

Le dépôt suit Moonfin et en diverge le moins possible :

| Chemin | Contenu |
|---|---|
| `lib/obmax/` | Code propre à OB Max (configuration, activation, thème, écran de démarrage, mises à jour, réglages). |
| `// OBMAX:` | Marque chaque point d'accroche dans les fichiers de Moonfin. La liste complète, et la marche à suivre pour suivre Moonfin, est dans [`OBMAX_CHANGES.md`](../OBMAX_CHANGES.md). |
| `server/enroll/` | Service d'activation (Go) : codes d'invitation, émission et renouvellement des certificats, page d'administration. |
| `tools/` | Scripts de publication (`release.ps1`) et de gestion des clés de signature. |
| `docs/obmax/` | Publication ([`RELEASE.md`](../docs/obmax/RELEASE.md)), conception de l'activation ([`V2_SPEC.md`](../docs/obmax/V2_SPEC.md)), recette ([`TEST_CHECKLIST.md`](../docs/obmax/TEST_CHECKLIST.md)), guide des invités. |
| `.github/workflows/obmax-macos.yml`, `obmax-windows.yml` | Construction du `.dmg` macOS et de l'installateur Windows sur GitHub Actions. |

Les autres fichiers (README de Moonfin, scripts de build des autres plateformes, modèles d'issues…) viennent de Moonfin et restent tels quels, pour faciliter les mises à jour.

## Contributions à Moonfin

Les correctifs utiles à tous sont proposés à Moonfin plutôt que gardés ici. Deux ont été intégrés : [#1893](https://github.com/Moonfin-Client/Moonfin-Core/pull/1893) (WebSocket avec certificat client) et [#1894](https://github.com/Moonfin-Client/Moonfin-Core/pull/1894) (import du certificat sur l'adresse https réellement jointe).

## Licence

OB Max est distribué sous **GNU GPL v2**, comme Moonfin ([`LICENSE`](../LICENSE)). Tout le mérite de l'application revient à l'équipe et aux contributeurs de [Moonfin](https://github.com/Moonfin-Client/Moonfin-Core). OB Max n'est ni affilié à Moonfin ni soutenu par ce projet.

Les issues sont désactivées sur ce dépôt : OB Max est un service privé, et les questions passent par son administrateur.
