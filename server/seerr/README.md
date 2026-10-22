# Seerr pour OB Max

Seerr reçoit les demandes de films et de séries des utilisateurs d'OB Max. L'app ne lui parle jamais directement : elle passe par le plugin **Moonbase** de Jellyfin (`/Moonfin/Seerr/…`), qui relaie vers Seerr sur le réseau local. Seerr n'est donc **pas** exposé par Caddy.

## Installation (sur le Pi)

1. Copier ce dossier sur le Pi, par exemple dans `~/seerr`.
2. `cd ~/seerr && sudo sh ./install.sh`
3. Ouvrir `http://<adresse du Pi>:5055` depuis le réseau local et suivre l'assistant :
   - serveur multimédia **Jellyfin**, adresse `http://<adresse du Pi>:8096` (pas `localhost` : Seerr tourne dans son propre conteneur) ;
   - connexion avec le compte administrateur Jellyfin ;
   - bibliothèques Films et Séries à synchroniser ;
   - **ne pas** configurer Radarr ni Sonarr (niveau 1 : les demandes sont traitées à la main).
4. *Paramètres > Notifications* : activer un canal (e-mail, Telegram…) pour être prévenu de chaque demande.

## Plugin Moonbase (dans Jellyfin)

1. *Tableau de bord > Extensions > Dépôts* : ajouter `https://raw.githubusercontent.com/Moonfin-Client/Plugin/refs/heads/master/manifest.json`.
2. Installer **Moonbase** depuis le catalogue, puis redémarrer Jellyfin.
3. Configuration du plugin, *Integrations* : adresse de Seerr `http://<adresse du Pi>:5055`, activer Seerr et Moonbase Sync.

## Mise à jour

`docker compose pull && docker compose up -d` dans `~/seerr`. L'image suit la version majeure 3 (`v3`) ; les données sont dans `config/` (à sauvegarder).
