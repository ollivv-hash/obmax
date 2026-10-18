# OB Max V2 — Inscription automatique par code d'invitation

> Brouillon à valider. Suite de `OBMAX_SPEC.md` (V1, recette validée le 18/10/2026).
> Objectif : un ami installe OB Max, saisit un code reçu de l'administrateur, et l'appareil obtient son propre certificat client sans fichier `.p12` ni mot de passe.

## 0. Décisions prises

| Sujet | Décision |
|---|---|
| Preuve pour le renouvellement | Preuve de possession de la clé, vérifiée par le service sur `enroll.*` (pas de réglage spécial dans Caddy) |
| Administration | Page web d'administration |
| Invitation | 1 code = 1 appareil, lié à un compte Jellyfin existant (créé à la main par l'administrateur) |
| Durée des certificats | 180 jours, renouvelés automatiquement aux deux tiers (à partir de 60 jours restants) |
| Coupure immédiate | Par Jellyfin : compte désactivé (tous ses appareils) ou *Tableau de bord > Appareils > Supprimer* (un seul appareil) |
| Hébergement | Conteneur Docker sur le Pi 5, à côté de Jellyfin |
| Caddy | v2.11.7 (paquet SynoCommunity sur le NAS) |

## 1. Architecture

```
Appareil OB Max ──TLS (sans certificat)──> enroll.example.com ─┐
                                                                      │  Caddy (NAS, :8443)
Appareil OB Max ──mTLS───────────────────> jellyfin.example.com┤
                                             └─ /obmax-admin/* ───────┤
                                                                      v
                                                     Pi 5 (192.168.0.206)
                                                     ├─ jellyfin        :8096
                                                     └─ obmax-enroll    :8787 (API publique)
                                                                        :8788 (admin)
```

- **`enroll.example.com`** : nouveau CNAME vers `dyn.example.com`, site Caddy **sans** `client_auth`. Il n'expose que l'API d'inscription (`/v1/*`, tout le reste en 404), vers le port 8787.
- **Page d'admin** : servie sous `https://jellyfin.example.com/obmax-admin/`, donc derrière le mTLS existant. Seul un appareil déjà certifié peut l'atteindre. Elle demande ensuite une connexion avec un **compte administrateur Jellyfin**, vérifiée auprès de Jellyfin. Elle tourne sur un port distinct (8788), jamais exposé via `enroll.*`.
- **Service `obmax-enroll`** : un seul binaire, deux ports. Il contient la CA intermédiaire, une base SQLite (invitations, appareils, journal) et les règles de limitation des tentatives.

## 2. Chaîne de certificats

### 2.1 Correction importante sur la révocation de l'intermédiaire

Si le `trust_pool` de Caddy contient **la racine**, tout certificat signé par **n'importe quel** intermédiaire issu de cette racine est accepté : l'app envoie l'intermédiaire avec son certificat, et Caddy remonte jusqu'à la racine. Retirer l'intermédiaire du pool ne révoquerait donc rien.

**Cible :** le `trust_pool` ne contient **que l'intermédiaire actif** (Go le traite comme ancre de confiance). La racine reste hors ligne et ne sert qu'à signer des intermédiaires. En cas de compromission du Pi, on retire l'intermédiaire du pool, on en signe un nouveau, et tous les appareils V2 se réinscrivent.

**Transition :** pendant la migration, le pool contient la racine **et** l'intermédiaire (révocation de l'intermédiaire impossible pendant cette période). Dès que les appareils de l'administrateur sont réinscrits en V2 (§7), on retire la racine du pool. Le certificat V1 `CN=admin` (signé directement par la racine) cesse alors de fonctionner, et le `.p12` V1 aussi.

### 2.2 Profils

| Certificat | Profil |
|---|---|
| Racine (existante) | EC P-256, `CN=Jellyfin Client CA`, 10 ans. Clé sur le PC de l'administrateur + sauvegarde dans le coffre de mots de passe, **supprimée du Pi** |
| Intermédiaire « OB Max Enrollment CA » (nouveau) | EC P-256, `basicConstraints=critical,CA:true,pathlen:0`, `keyUsage=critical,keyCertSign,cRLSign`, `extendedKeyUsage=clientAuth`, 3 ans. Clé sur le Pi (volume Docker, droits 600) |
| Certificat d'appareil | EC P-256, clé générée **sur l'appareil**. `CN=<utilisateur Jellyfin>/<appareil>`, `O=OB Max`, `keyUsage=critical,digitalSignature`, `extendedKeyUsage=clientAuth`, numéro de série aléatoire 128 bits, `notBefore` = maintenant − 5 min (horloges des TV), validité 180 jours. Le service ignore le sujet du CSR et impose le sien |

### 2.3 Cérémonie unique de création de l'intermédiaire (sur le PC)

Script fourni : `server/enroll/tools/make-intermediate.ps1`. Il génère la clé et le CSR de l'intermédiaire, les signe avec `ca.key`, et produit `obmax-enroll-ca.crt` et `obmax-enroll-ca.key`, à copier sur le Pi. Ensuite :
- supprimer `ca.key` du Pi (`~/caddy/certs/`) ;
- garder `ca.key` sur le PC et dans le coffre de mots de passe ;
- sauvegarder `obmax-enroll-ca.key` hors du Pi.

## 3. API publique (`enroll.example.com`)

Toutes les réponses sont en JSON, avec des messages d'erreur génériques : on n'indique jamais si un code existe.

### `POST /v1/enroll`

```json
{
  "code": "7KQM-4X2P-DH9W",
  "csr": "-----BEGIN CERTIFICATE REQUEST-----…",
  "device": { "name": "SHIELD Android TV", "platform": "androidTv", "appVersion": "2.0.0" }
}
```

Le service :
1. normalise le code (majuscules, sans tirets) et cherche son empreinte SHA-256 en base ;
2. vérifie que le code n'est ni expiré (48 h), ni utilisé, ni annulé ;
3. vérifie le CSR : signature valide, clé EC P-256 ;
4. émet le certificat, marque le code utilisé et enregistre l'appareil.

Il répond `200 { "certificateChain": "<feuille + intermédiaire, PEM>", "deviceId": "…", "jellyfinUsername": "paul", "serverUrl": "https://jellyfin.example.com", "notAfter": "…" }`.

Erreurs : `400 invalid_request`, `403 invalid_code` (code inconnu, expiré, déjà utilisé ou annulé : même réponse dans tous les cas), `429 rate_limited`.

### `POST /v1/renew`

```json
{ "deviceId": "…", "certificateChain": "<chaîne actuelle>", "csr": "<CSR avec la MÊME clé publique>" }
```

Le CSR est signé par la clé privée de l'appareil : c'est la preuve de possession. Un attaquant qui rejouerait une requête capturée n'obtiendrait qu'un certificat pour une clé qu'il ne possède pas.

Le service vérifie :
- que la chaîne remonte à l'intermédiaire actif ;
- que le certificat n'est pas expiré (sinon, réinscription avec un nouveau code) ;
- que le numéro de série correspond au dernier émis pour `deviceId` ;
- que l'appareil n'est pas révoqué ;
- que la clé publique du CSR est identique à celle du certificat.

Il émet alors un nouveau certificat de 180 jours.

Erreurs : `403 revoked`, `403 invalid_certificate`, `429 rate_limited`.

### `GET /v1/health`

Répond `200` (pour la supervision).

### Limitation des tentatives

La version standard de Caddy ne limite pas le débit : c'est donc le service qui s'en charge.
- Au plus 5 échecs de code par IP et par heure, puis `429` pendant une heure.
- Au-delà de 50 échecs par heure toutes IP confondues, `/v1/enroll` est suspendu 15 minutes.
- Codes de 12 caractères en base32 Crockford, soit environ 60 bits (format `XXXX-XXXX-XXXX`, sans caractères ambigus). Seule l'empreinte du code est stockée.

## 4. Page d'administration (`/obmax-admin/`)

- **Connexion** : identifiant et mot de passe Jellyfin, envoyés à `POST /Users/AuthenticateByName`. L'accès n'est accordé que si `Policy.IsAdministrator` est vrai. Session de 12 h par cookie `HttpOnly; Secure; SameSite=Strict`, avec jeton CSRF sur les formulaires.
- **Inviter** : choix d'un utilisateur Jellyfin (liste lue avec le jeton de l'admin) et d'un libellé facultatif (« Shield de Paul »). La page affiche le code, son expiration, un QR code, et un message prêt à copier : lien de l'APK et code.
- **Invitations en attente** : utilisateur, libellé, création, expiration, bouton « Annuler ».
- **Appareils** : utilisateur, nom et plateforme, date d'inscription, dernier renouvellement, expiration du certificat, état. Boutons « Révoquer » (bloque le renouvellement) et rappel du chemin Jellyfin pour une coupure immédiate.
- **Journal** : inscriptions, renouvellements, échecs de code (IP), révocations.
- Interface en français, aux couleurs d'OB Max, rendue côté serveur. Pas de framework JavaScript.

## 5. Côté app (OB Max)

### 5.1 Premier lancement

L'écran « Installer votre certificat » devient « Activer OB Max » :
- **Choix principal : « J'ai un code d'invitation »**
  - Mobile : champ de saisie (`XXXX-XXXX-XXXX`, tirets automatiques, majuscules).
  - TV : champ saisi à la télécommande, **ou** QR code qui ouvre sur le téléphone une page du réseau local où taper le code (même mécanisme que l'envoi du `.p12` en V1).
- **Choix secondaire : « Importer un fichier .p12 »** (flux V1 inchangé, utile en secours).

Une fois le code validé :
1. l'app génère la paire de clés EC P-256 ;
2. elle construit le CSR (PKCS#10) ;
3. elle appelle `/v1/enroll` ;
4. elle enregistre la chaîne et la clé comme en V1 (`StoredClientCertificate` + `installClientCertificates`), plus des métadonnées (`deviceId`, `enrolled: true`, `notAfter`) ;
5. elle fait le test de connexion habituel ;
6. elle ouvre l'écran de connexion **avec l'identifiant pré-rempli** (`jellyfinUsername`), avec le mot de passe ou Quick Connect.

Messages d'erreur en français : « Ce code n'est pas valide ou a expiré », « Trop d'essais, réessayez dans une heure », « Service d'activation injoignable ».

### 5.2 Renouvellement automatique

- Au démarrage puis une fois par jour : si le certificat a été obtenu par inscription et qu'il lui reste moins de 60 jours, l'app appelle `/v1/renew` en silence et remplace le certificat.
- En cas d'échec, elle réessaie au lancement suivant. Si l'appareil est révoqué, elle ne fait rien : le certificat expirera et l'écran d'activation reviendra au démarrage (comportement V1 déjà en place).
- *Réglages > Compte et sécurité > Certificat* affiche « Délivré par OB Max, expire le …, renouvelé automatiquement » et un bouton « Renouveler maintenant ».

### 5.3 Contraintes

- Le CSR est construit avec `pointycastle`, déjà présent : **aucune nouvelle dépendance**.
- La clé reste stockée comme en V1 (stockage sécurisé, `ClientCertificateVault` sous Android). Une clé non exportable de l'AndroidKeyStore est incompatible avec dart:io et le reste.
- Nouvelle constante : `kObMaxEnrollUrl` (défaut `https://enroll.example.com`).
- Tout le code app reste dans `lib/obmax/`, sans nouveau hook upstream prévu.

## 6. Exploitation

- **Image Docker** arm64, `restart: unless-stopped`, volume `obmax-enroll-data` (SQLite, clé et certificat de l'intermédiaire, droits 600), variables `JELLYFIN_URL=http://192.168.0.206:8096` et `PUBLIC_SERVER_URL=https://jellyfin.example.com`.
- **Caddyfile** (extraits fournis, à coller par l'administrateur) :
  - nouveau site `enroll.example.com` : `handle /v1/*` vers `reverse_proxy 192.168.0.206:8787`, sinon `respond 404` ;
  - dans `jellyfin.example.com` : `handle_path /obmax-admin/*` vers `reverse_proxy 192.168.0.206:8788` ;
  - `trust_pool` : racine et intermédiaire pendant la transition, puis intermédiaire seul.
- **Sauvegarde** : copie quotidienne du volume vers le NAS. Clé de l'intermédiaire aussi dans le coffre de mots de passe.
- **Supervision** : `GET /v1/health`, et dans la page d'admin une alerte quand l'intermédiaire expire dans moins de 6 mois.

## 7. Migration

1. Cérémonie de l'intermédiaire (§2.3), puis suppression de `ca.key` du Pi.
2. Déploiement du service, DNS `enroll.*`, blocs Caddy, `trust_pool` = racine + intermédiaire.
3. Release OB Max 2.0.0 (OTA).
4. L'administrateur crée une invitation par appareil à lui (téléphone, Shield), puis les réinscrit : *Réglages > Compte et sécurité > Certificat > Remplacer par un code*.
5. Une fois tous ses appareils sur des certificats V2 : retrait de la racine du `trust_pool`. L'ancien `.p12` cesse de fonctionner.
6. Invitations des amis.

## 8. Hors périmètre V2

Création automatique des comptes Jellyfin, iOS et iPadOS, bascule LAN/WAN, supervision externe (alertes par mail).

## 9. Recette V2

| # | Test |
|---|---|
| V1 | Installation neuve, code valide : activation, connexion avec l'identifiant pré-rempli, sur mobile en 4G et sur la Shield |
| V2 | Shield : saisie du code depuis le téléphone par QR code |
| V3 | Codes faux, expirés, déjà utilisés, annulés : même message ; 6e essai depuis la même IP : « Trop d'essais » |
| V4 | Page d'admin : refusée sans certificat (bloquée par Caddy) et avec un compte non administrateur ; invitation, annulation, liste des appareils |
| V5 | Renouvellement : avec une validité de test courte, le certificat est renouvelé en silence et l'app reste connectée |
| V6 | Révocation : renouvellement refusé, puis après expiration (validité de test) retour à l'écran d'activation |
| V7 | Coupure immédiate par Jellyfin (suppression de l'appareil) |
| V8 | Transition : `.p12` V1 et certificats V2 acceptés, puis seulement V2 après retrait de la racine |
| V9 | Redémarrage du Pi et du NAS : service relancé, données conservées |
| V10 | Mise à jour de l'app par OTA depuis la 1.0.1 : données et certificat V1 conservés |

## 10. Points à valider par l'administrateur

1. **Langage du service** : je propose **Go**. Un seul binaire statique, une image Docker de quelques Mo, une bibliothèque `crypto/x509` complète dans le standard, peu de mémoire sur le Pi. L'alternative est Python (FastAPI) : plus lisible, mais une image plus lourde et plus de dépendances.
2. **Emplacement du code serveur** : je propose un dossier `server/enroll/` dans le dépôt `obmax`. C'est un seul dépôt, sans impact sur les rebases Moonfin (nouveau dossier), et le code sera public avec le reste, sans aucun secret dedans.
3. **Fin de la racine dans le `trust_pool`** (§2.1) : d'accord pour que l'ancien `.p12` cesse de fonctionner une fois la migration finie ?
