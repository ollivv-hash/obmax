# Caddy pour OB Max (sur le Raspberry Pi)

Point d'entrée public d'OB Max : Jellyfin et la page d'admin, protégés par certificat client (CA d'activation OB Max), et l'API d'activation, sans certificat. Caddy tourne sur le même Pi que Jellyfin et `obmax-enroll`, en réseau hôte, sur les ports 80 et 443.

Il était auparavant sur le NAS. Le déplacer a supprimé un aller-retour réseau par film (NAS → Pi → NAS → Internet) et libéré le processeur du NAS, qui passait l'essentiel de son temps à chiffrer les flux.

## Installation

1. Copier ce dossier sur le Pi (`~/caddy`), avec `Caddyfile` (domaines réels, à partir de `Caddyfile.example`) et `ca/obmax-enroll-ca.crt`.
2. `cd ~/caddy && sudo sh ./install.sh` : vérifie que 80 et 443 sont libres, valide le Caddyfile et démarre Caddy.
3. Jellyfin, *Réseau > Proxys connus* : ajouter `127.0.0.1` et l'adresse de la passerelle Docker de Jellyfin (souvent `172.18.0.1`), sinon tous les clients semblent locaux.
4. `obmax-enroll` : `ENROLL_TRUSTED_PROXIES` doit contenir `127.0.0.1/32`.
5. Box : rediriger TCP 80 et 443 vers le Pi, puis `sudo docker compose restart` pour obtenir tout de suite les certificats Let's Encrypt.

Retour arrière : rediriger de nouveau 80 et 443 vers l'ancien Caddy.

## Révocation

Retirer `obmax-enroll-ca.crt` du `trust_pool` coupe tous les appareils d'un coup. Révoquer un appareil seul : page d'admin, puis suppression de l'appareil dans Jellyfin pour une coupure immédiate.
