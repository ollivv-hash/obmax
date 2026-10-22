# Caddy pour OB Max (sur le Raspberry Pi)

Point d'entrée public d'OB Max : Jellyfin et la page d'admin, protégés par certificat client (CA d'activation OB Max), et l'API d'activation, sans certificat. Caddy tourne sur le même Pi que Jellyfin et `obmax-enroll`, en réseau hôte, sur les ports 80 et 443.

Il était auparavant sur le NAS. Le déplacer a supprimé un aller-retour réseau par film (NAS → Pi → NAS → Internet) et libéré le processeur du NAS, qui passait l'essentiel de son temps à chiffrer les flux.

## Installation

1. Copier ce dossier sur le Pi (`~/obmax-caddy`), avec `Caddyfile` (domaines réels, à partir de `Caddyfile.example`) et `ca/obmax-enroll-ca.crt`.
2. `cd ~/obmax-caddy && sudo sh ./install.sh` : vérifie que 80 et 443 sont libres, valide le Caddyfile et démarre Caddy.
3. Jellyfin, *Réseau > Proxys connus* : ajouter l'adresse sous laquelle Caddy arrive chez Jellyfin (l'adresse du Pi, `127.0.0.1`, ou la passerelle Docker `172.18.0.1`), puis **redémarrer Jellyfin** : ce réglage n'est pris en compte qu'au redémarrage. Sinon tous les clients semblent locaux. Note : le conteneur Jellyfin ne publie 8096 que sur l'adresse réseau du Pi, d'où `reverse_proxy <adresse du Pi>:8096`.
4. `obmax-enroll` : `ENROLL_TRUSTED_PROXIES` doit contenir `127.0.0.1/32`.
5. Box : rediriger TCP 80 et 443 vers le Pi, puis `sudo docker compose restart` pour obtenir tout de suite les certificats Let's Encrypt.

Retour arrière : rediriger de nouveau 80 et 443 vers l'ancien Caddy.

## Révocation

Retirer `obmax-enroll-ca.crt` du `trust_pool` coupe tous les appareils d'un coup. Révoquer un appareil seul : page d'admin, puis suppression de l'appareil dans Jellyfin pour une coupure immédiate.
