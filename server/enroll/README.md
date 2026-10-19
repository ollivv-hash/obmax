# obmax-enroll — service d'activation d'OB Max (V2)

Le service délivre un certificat client à chaque appareil à partir d'un code d'invitation à usage unique. Il renouvelle ensuite ce certificat automatiquement et fournit une page d'administration. La conception est décrite dans `docs/obmax/V2_SPEC.md`.

- **API publique** (`:8787`), derrière `https://enroll.example.com` : `POST /v1/enroll`, `POST /v1/renew`, `GET /v1/health`.
- **Page d'admin** (`:8788`), derrière `https://jellyfin.example.com/obmax-admin/` (mTLS, puis connexion avec un compte administrateur Jellyfin).
- Écrit en Go, avec la seule bibliothèque standard. L'état tient dans un fichier `data/state.json`, et l'intermédiaire dans `data/ca/`.
- Le service n'accepte que les requêtes venant de Caddy (`ENROLL_TRUSTED_PROXIES`, 192.168.0.101) : depuis le réseau local, on ne peut pas contourner le mTLS en appelant directement les ports du Pi.

## Déploiement

### 1. Créer la CA intermédiaire (une seule fois, sur le PC qui détient `ca.key`)

```powershell
.\server\enroll\tools\make-intermediate.ps1 -RootCert <chemin>\ca.crt -RootKey <chemin>\ca.key -OutDir E:\obmax-keys\enroll-ca
```

Le script produit `obmax-enroll-ca.crt` et `obmax-enroll-ca.key`, valables 3 ans. Mets la clé dans ton coffre de mots de passe.

**Puis supprime `ca.key` du Pi** (`~/caddy/certs/ca.key`). Il doit rester uniquement sur le PC et dans le coffre.

### 2. Installer le service sur le Pi

Copie le dossier `server/enroll` sur le Pi (par exemple dans `~/obmax-enroll`), puis l'intermédiaire dans `data/ca/` :

```bash
mkdir -p ~/obmax-enroll/data/ca
# depuis le PC : scp E:\obmax-keys\enroll-ca\obmax-enroll-ca.* pi@192.168.0.206:~/obmax-enroll/data/ca/
sudo chown -R 65532:65532 ~/obmax-enroll/data
sudo chmod 700 ~/obmax-enroll/data ~/obmax-enroll/data/ca
sudo chmod 600 ~/obmax-enroll/data/ca/obmax-enroll-ca.key
cd ~/obmax-enroll && docker compose up -d --build
docker compose logs -f   # attendu : CA "OB Max Enrollment CA" valid until …
```

L'image ne contient ni shell ni gestionnaire de paquets, et le service tourne sous un utilisateur non root (65532). Le conteneur utilise le réseau de l'hôte, ce qui conserve la vraie adresse de Caddy.

### 3. DNS

Crée un CNAME `enroll.example.com` vers `dyn.example.com`, comme pour `jellyfin`.

### 4. Caddy (NAS)

Fichier `/var/packages/caddy/var/Caddyfile`. Copie d'abord `obmax-enroll-ca.crt` dans `/var/packages/caddy/var/`.

**a. Nouveau site, sans certificat client :**

```caddy
enroll.example.com {
	handle /v1/* {
		reverse_proxy 192.168.0.206:8787
	}
	handle {
		respond 404
	}
}
```

**b. Dans le site `jellyfin.example.com` existant**, ajoute la page d'admin et l'intermédiaire au `trust_pool` :

```caddy
jellyfin.example.com {
	tls {
		client_auth {
			mode require_and_verify
			# Transition : racine (ancien .p12) + intermédiaire (appareils V2).
			# Une fois tous tes appareils réinscrits, retire ca.crt (voir étape 7).
			trust_pool file /var/packages/caddy/var/ca.crt /var/packages/caddy/var/obmax-enroll-ca.crt
		}
	}

	handle /obmax-admin/* {
		reverse_proxy 192.168.0.206:8788
	}
	handle {
		reverse_proxy 192.168.0.206:8096
	}
}
```

Garde tes autres options existantes (protocoles TLS, en-têtes, journaux). Si ton bloc contient déjà un `reverse_proxy` nu, mets-le dans le `handle { … }` final, comme ci-dessus.

Vérifie la configuration, puis recharge Caddy :

```bash
/var/packages/caddy/target/bin/caddy validate --config /var/packages/caddy/var/Caddyfile
```

Recharge ensuite depuis le Centre de paquets DSM (Arrêter, puis Exécuter), ou avec `caddy reload` si tu l'utilises déjà.

### 5. Vérifications

- `https://enroll.example.com/v1/health` répond `{"status":"ok"}`, **sans** certificat client.
- `https://enroll.example.com/obmax-admin/` répond 404.
- `https://jellyfin.example.com/obmax-admin/`, depuis un navigateur qui a le certificat, affiche la page de connexion. Connecte-toi avec ton compte administrateur Jellyfin.

### 6. Activer un appareil

Dans la page d'admin, choisis le compte Jellyfin et le libellé de l'appareil, puis clique sur **Créer le code**. Envoie le message proposé. Le code est valable 48 h et pour un seul appareil.

### 7. Fin de la migration (retrait de la racine)

Tant que la racine reste dans le `trust_pool`, l'ancien `.p12` fonctionne. Révoquer l'intermédiaire ne couperait alors rien. Dans l'ordre :

1. **Appareils OB Max** : tous ceux qui servent apparaissent dans la page d'admin (certificat V2).
2. **Navigateurs** : l'ancien `.p12` donne aussi accès à la page d'admin et à l'interface web de Jellyfin. Il faut le remplacer par un certificat émis par l'intermédiaire :
   ```powershell
   .\server\enroll\tools\make-browser-cert.ps1 -Name ollivv-navigateur
   ```
   Le script crée `E:\obmax-keys\browser\ollivv-navigateur.p12` (RSA 2048, valable 2 ans au plus et jamais au-delà de l'intermédiaire). Le mot de passe se saisit à l'invite d'openssl. Importe ce fichier dans Chrome sur chaque appareil, puis vérifie la page d'admin en choisissant ce certificat. Un tel certificat n'apparaît pas dans la page d'admin et ne peut pas y être révoqué.
3. **Caddy** : copie `tools/nas-finish-migration.sh` sur le NAS, puis lance `sudo sh ./nas-finish-migration.sh`. Le script sauvegarde le Caddyfile, retire `ca.crt` du `trust_pool`, valide la configuration et redémarre Caddy, ou restaure tout si la validation échoue. Il affiche la commande de retour arrière.
4. **Vérifications** : les apps et Chrome (nouveau certificat) fonctionnent, et l'ancien `.p12` est refusé.

Ensuite, retirer l'intermédiaire du pool coupe tous les appareils V2 d'un coup. La clé racine ne sert plus qu'à signer le prochain intermédiaire (2029) : garde-la chiffrée, dans le coffre de mots de passe uniquement.

## Exploitation

- **Sauvegarde** : copie `~/obmax-enroll/data/` vers le NAS, par exemple chaque nuit avec `rsync`. La clé de l'intermédiaire est aussi dans le coffre.
- **Révoquer un appareil** : bouton **Révoquer** dans la page d'admin (plus de renouvellement, donc expiration au plus tard en 180 jours). Pour une coupure **immédiate** : *Jellyfin > Tableau de bord > Appareils > Supprimer* (l'appareil seul) ou désactiver le compte (tous ses appareils).
- **Mettre à jour le service** : copie ce dossier, **sans `data/`**, sur le Pi (par exemple dans `~/obmax-enroll-update`), puis `sudo sh ./update.sh` depuis ce dossier. Le script sauvegarde l'ancien code, remplace les fichiers de `~/obmax-enroll`, reconstruit le conteneur et vérifie la santé. `data/` (CA, appareils, journal) n'est jamais touché.
- **Renouveler l'intermédiaire** (la page d'admin prévient 6 mois avant) : refaire l'étape 1 dans un nouveau dossier, placer le nouveau fichier dans `data/ca/` et l'ajouter au `trust_pool` à côté de l'ancien, redémarrer le service. Les appareils obtiennent un certificat du nouvel intermédiaire à leur prochain renouvellement. Retire l'ancien du pool quand il a expiré.

## Variables d'environnement

| Variable | Défaut | Rôle |
|---|---|---|
| `ENROLL_DATA_DIR` | `/data` | `state.json` et `ca/` |
| `ENROLL_PUBLIC_ADDR` / `ENROLL_ADMIN_ADDR` | `:8787` / `:8788` | Ports d'écoute |
| `ENROLL_ADMIN_BASE_PATH` | `/obmax-admin` | Chemin de la page d'admin |
| `JELLYFIN_URL` | `http://192.168.0.206:8096` | Jellyfin, pour la connexion admin et la liste des comptes |
| `PUBLIC_SERVER_URL` | `https://jellyfin.example.com` | Renvoyé à l'app après l'inscription |
| `ENROLL_TRUSTED_PROXIES` | `192.168.0.101/32,127.0.0.1/32` | Seules adresses acceptées (Caddy) |
| `ENROLL_CERT_VALIDITY` | `4320h` (180 jours) | Durée des certificats d'appareil (raccourcir pour tester le renouvellement) |
| `ENROLL_INVITE_VALIDITY` | `48h` | Durée de validité d'un code |
| `ENROLL_APK_URL` | page de la dernière release | Lien inclus dans le message d'invitation |
| `ENROLL_ALLOW_DIRECT` | vide | Développement uniquement : accepte les appels qui ne passent pas par Caddy |
| `ENROLL_INSECURE_COOKIES` | vide | Développement uniquement : cookies sans `Secure` (HTTP) |

## Développement

```powershell
$env:PATH = "E:\go\bin;$env:PATH"
cd server\enroll
go vet ./...
go test ./...
```

Test de bout en bout côté app (`test/obmax/obmax_enroll_e2e_test.dart`). Il faut un service lancé en local (`ENROLL_ALLOW_DIRECT=1`) avec une invitation, et éventuellement un serveur TLS qui exige un certificat client de l'intermédiaire. Indique-les par des variables d'environnement :

```powershell
$env:OBMAX_E2E_ENROLL = "http://127.0.0.1:18787"
$env:OBMAX_E2E_CODE = "<code d'une invitation en attente>"
$env:OBMAX_E2E_TLS = "127.0.0.1:18443"   # facultatif
flutter test test/obmax/obmax_enroll_e2e_test.dart
```

Sans `OBMAX_E2E_ENROLL`, le test est ignoré.
