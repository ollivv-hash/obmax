# OB Max — Réinitialisation du mot de passe (spec)

Version cible : **2.2**. Destinataire : Claude Code.

## 0. Principes du projet (rappel)

- Diff minimal avec l'upstream Moonfin-Core (GPL v2).
- Code OB Max dans `lib/obmax/` ; points d'accroche dans le code upstream courts et marqués `// OBMAX:`.
- `OBMAX_CHANGES.md` à jour à chaque changement touchant l'upstream.
- Aucun secret ni identité réelle de l'administrateur dans le dépôt public : utiliser `example.com` et « l'administrateur ».
- Commits petits et thématiques.
- Demander avant toute décision structurante (voir section 9).

## 1. Objectif et contexte

Permettre à un ami de récupérer l'accès à son compte Jellyfin sans intervention manuelle systématique de l'administrateur.

- Jellyfin n'a pas de champ e-mail et pas de reset automatique. Son flux PIN natif écrit un fichier sur le serveur et n'est accepté que depuis le LAN : **on ne l'utilise pas**.
- Architecture : app OB Max → Caddy (`obmax-caddy`, mTLS obligatoire) → `obmax-enroll` (service maison) → API Jellyfin. Home Assistant (conteneur `homeassistant`) sert à notifier/valider sur le téléphone de l'administrateur.
- Chaque certificat client est lié à **un** utilisateur Jellyfin et **une** machine (base d'enroll).

## 2. Flux fonctionnel

1. Écran de login : lien « Mot de passe oublié ? » → saisie de l'identifiant (pré-rempli si déjà saisi).
2. L'app envoie `POST /reset-request {"username": "..."}` à enroll via Caddy/mTLS.
3. Réponse **toujours identique** (anti-énumération), HTTP 202 :
   « Si ce compte existe, un e-mail vous sera envoyé avec un nouveau mot de passe. »
4. Enroll applique la règle de décision (section 3), puis journalise.

## 3. Règle de décision (côté enroll)

| Cas | Action |
|---|---|
| Certificat lié au **même** utilisateur que `username` ET e-mail enregistré | Reset automatique + e-mail + notification HA informative |
| Certificat lié à un **autre** utilisateur (ex. appareil partagé) ET e-mail enregistré | Demande « en attente » + notification HA actionnable Approuver / Refuser |
| Aucun e-mail enregistré, ou utilisateur inexistant dans Jellyfin | Aucun reset ; notification HA informative |
| Limite de débit dépassée (section 7) | Demande ignorée ; notification HA informative |

- Le critère « IP habituelle » est abandonné (validé) : chaque certificat étant lié à un utilisateur, il est superflu. L'IP est seulement **journalisée** et **affichée dans la notification**.
- La réponse HTTP est identique dans tous les cas, et le temps de réponse ne doit pas révéler le cas (traitement asynchrone après la réponse).

## 4. Identité du certificat et IP via Caddy

- Caddy ajoute à la requête vers enroll, pour `/reset-request` : l'identité du certificat client (ex. `X-Client-Cert-Subject {http.request.tls.client.subject}` et/ou `X-Client-Cert-Fingerprint {http.request.tls.client.fingerprint}`) et `X-Forwarded-For` (IP réelle).
- Caddy doit **écraser** (`header_up` avec valeur fixée) tout header équivalent envoyé par le client.
- Enroll **refuse** (403) toute requête portant ces headers qui ne provient pas de l'IP/du réseau Docker de `obmax-caddy` (ou, mieux, qui ne présente pas un secret partagé Caddy→enroll en header). Une requête sans headers, ou sans origine Caddy, est refusée.
- Enroll retrouve certificat → utilisateur + machine dans sa base existante.
- Claude Code vérifie les placeholders exacts disponibles dans la version de Caddy en place et documente le choix (CN vs empreinte).
- `/reset-decision` et le webhook HA ne sont **jamais** exposés via Caddy public.

## 5. Adresses e-mail

- Stockées dans la base d'enroll : table `user_emails (username PRIMARY KEY, email, updated_at)`. Pas dans Jellyfin.
- Gestion : via la **page admin d'enroll** (section 5 bis, à créer). Une CLI minimale (`docker exec obmax-enroll … email set|list`) est tolérée comme secours, sans être le moyen principal.
- Validation basique du format ; aucune adresse dans les logs applicatifs (masquer : `o***@example.com`).

## 5 bis. Page admin d'enroll (nouvelle)

Accès :
- Route `/admin` servie par enroll, exposée via Caddy **sur le même hôte mTLS**.
- Autorisation : le certificat client présenté doit être lié à un utilisateur Jellyfin **administrateur** (vérifié via l'API Jellyfin, `Policy.IsAdministrator`, avec un cache court). Sinon 403. Pas de login/mot de passe supplémentaire.
- Protection CSRF sur toutes les actions (POST), en-têtes de sécurité (`X-Frame-Options: DENY`, CSP stricte), aucune ressource externe (pas de CDN).
- Français, sobre, aux couleurs OB Max (`#080A23`, or `#EDA631`), utilisable sur mobile.

Fonctions v1 :
1. **Utilisateurs** : liste des utilisateurs Jellyfin (lue via l'API), avec pour chacun son adresse e-mail (ajouter / modifier / supprimer) et ses appareils/certificats liés (lecture seule).
2. **Demandes en attente** : approuver / refuser (même effet que la notification HA ; la première décision gagne).
3. **Journal** : demandes de reset des 90 derniers jours (date, utilisateur, machine, IP, décision, résultat d'envoi), filtrable par utilisateur.
4. **Reset manuel** : bouton « Réinitialiser et envoyer par e-mail » sur un utilisateur (même circuit que l'auto, journalisé `manual`).

Hors v1 : gestion des certificats (révocation, émission) depuis cette page.

## 6. Génération, application et envoi

### Mot de passe temporaire
- CSPRNG (`secrets` / équivalent), 4 groupes de 4 séparés par `-`, alphabet sans caractères ambigus (exclure `0 O 1 l I`).
- Jamais journalisé, jamais stocké en base, jamais dans la notification HA.

### Application côté Jellyfin
- `POST /Users/{userId}/Password` avec `Authorization: MediaBrowser Token="<clé>"` et body `{"NewPw": "..."}`.
- **Claude Code vérifie le comportement réel sur la version de Jellyfin en place** (certaines versions exigent `{"ResetPassword": true}` puis `{"NewPw": "..."}`) et le documente dans la doc d'exploitation.
- Clé API dédiée nommée « obmax-enroll-reset », fournie en secret Docker/variable d'environnement. Recherche de `userId` par nom via l'API.

### E-mail
- SMTP dédié (ex. `noreply@example.com`), STARTTLS port 587, identifiants en variables d'environnement / secret Docker, jamais dans git.
- Français, texte simple + HTML sobre, **aucun lien**. Contenu : mot de passe temporaire, consigne de le changer dans Réglages > Compte, et « si vous n'êtes pas à l'origine de cette demande, prévenez l'administrateur ».
- Ordre d'exécution : **appliquer le mot de passe dans Jellyfin, puis envoyer l'e-mail**. L'utilisateur a de toute façon perdu son mot de passe, appliquer d'abord ne lui retire rien.
  - Échec de l'API Jellyfin → aucun e-mail, journal + notification HA « reset échoué ».
  - Échec SMTP → journal + notification HA « reset appliqué, e-mail non envoyé » (sans le mot de passe) ; l'administrateur refait un reset manuel.

## 7. Garde-fous

- Demande en attente expire après **24 h** (statut `expired`, notification HA optionnelle).
- Max **1 demande par utilisateur par heure** et **5 par certificat par 24 h** ; au-delà : ignorée + notification HA.
- Journal (table `reset_requests`) : id, horodatage, username, certificat/machine, IP, décision (auto / approuvée / refusée / expirée / ignorée / sans e-mail / inexistant), résultat d'envoi. Mot de passe jamais journalisé.
- Une décision HA ne s'applique qu'une fois, et seulement sur une demande `pending` non expirée.

## 8. Intégration Home Assistant

- Enroll → HA : `POST http://homeassistant:8123/api/webhook/<webhook_id>` (réseau interne Docker/LAN), `webhook_id` secret, payload `{id, kind, username, machine, ip, message}` avec `kind` ∈ `info` | `approval`.
- Enroll ← HA : `POST /reset-decision {"id": "...", "decision": "approve"|"refuse"}` avec header `X-Reset-Secret` (secret partagé), accessible uniquement en interne.
- YAML HA attendu (à fournir comme livrable, valeurs secrètes dans `secrets.yaml`) :

```yaml
# configuration.yaml
rest_command:
  obmax_reset_decision:
    url: "http://obmax-enroll:PORT/reset-decision"
    method: post
    headers:
      X-Reset-Secret: !secret obmax_reset_secret
      Content-Type: application/json
    payload: '{"id": "{{ id }}", "decision": "{{ decision }}"}'

# automations.yaml
- alias: "OB Max — demande de reset"
  trigger:
    - platform: webhook
      webhook_id: !secret obmax_reset_webhook_id
      allowed_methods: [POST]
      local_only: true
  action:
    - choose:
        - conditions: "{{ trigger.json.kind == 'approval' }}"
          sequence:
            - service: notify.mobile_app_TELEPHONE_ADMIN
              data:
                title: "OB Max — approbation requise"
                message: "{{ trigger.json.message }}"
                data:
                  actions:
                    - action: "OBMAX_APPROVE_{{ trigger.json.id }}"
                      title: "Approuver"
                    - action: "OBMAX_REFUSE_{{ trigger.json.id }}"
                      title: "Refuser"
      default:
        - service: notify.mobile_app_TELEPHONE_ADMIN
          data:
            title: "OB Max — reset"
            message: "{{ trigger.json.message }}"

- alias: "OB Max — décision reset"
  trigger:
    - platform: event
      event_type: mobile_app_notification_action
  condition:
    - "{{ trigger.event.data.action.startswith('OBMAX_') }}"
  action:
    - service: rest_command.obmax_reset_decision
      data:
        id: "{{ trigger.event.data.action.split('_', 2)[2] }}"
        decision: "{{ 'approve' if trigger.event.data.action.startswith('OBMAX_APPROVE_') else 'refuse' }}"
```

- Claude Code ajuste ce YAML (nom du service notify, port, noms de conteneurs) après vérification auprès de l'administrateur, et le livre dans `docs/` ou `ops/`.

## 9. À arbitrer / zones sensibles — s'arrêter et me demander

Arbitrages rendus : critère IP abandonné ; page admin à créer (5 bis) ; changement de mot de passe proposé après connexion (10).

Zones sensibles :
- Autorisation de la page admin (5 bis) : présenter le mécanisme et le diff Caddy avant mise en service.
- Stockage sécurisé, certificats et mTLS côté app : ne rien modifier sans accord.
- Schéma de base d'enroll : toute migration (nouvelles tables) → proposer le script, sauvegarde préalable, attendre validation.
- Ajout de toute dépendance réseau (bibliothèque SMTP, client HTTP) : justifier et demander.
- Toute modification de la config Caddy : **montrer le diff avant de l'appliquer**.
- Portée de la clé API Jellyfin : vérifier ce que « obmax-enroll-reset » peut faire (une clé API Jellyfin est de fait admin) ; documenter, ne jamais l'exposer au-delà d'enroll.

Limite connue : Jellyfin n'a pas de « changement obligatoire à la prochaine connexion » ; le mot de passe temporaire reste valable tant que l'utilisateur ne le change pas.

## 10. App OB Max (hook)

- Code dans `lib/obmax/reset_password/` (écran/dialogue de saisie, appel HTTP via le client mTLS existant d'OB Max, sans nouvelle dépendance).
- Un seul point d'accroche upstream, court, marqué `// OBMAX:`, pour le lien « Mot de passe oublié ? » sur l'écran de login.
- Textes via clés `.arb` FR (ajouter les clés dans le fichier FR ; fallback EN/autres selon la convention existante) : lien, titre, champ identifiant, bouton, message neutre de réponse, erreurs réseau.
- Gestion d'erreur : en cas d'échec réseau/mTLS, message générique distinct du message neutre ; ne jamais indiquer si le compte existe.

### Changement de mot de passe après un reset

- Quand un reset est appliqué, enroll pose un indicateur `reset_pending_change` sur l'utilisateur (validité 7 jours).
- Après chaque login réussi, l'app appelle `GET /reset-status` sur enroll (mTLS, l'utilisateur est déduit du certificat). Si l'indicateur est actif, elle affiche l'écran « Choisissez votre nouveau mot de passe » : nouveau mot de passe + confirmation, avec indicateur de robustesse simple (8 caractères minimum).
- Le changement passe par l'**API Jellyfin standard avec la session de l'utilisateur** (`POST /Users/{id}/Password` avec `CurrentPw` = mot de passe temporaire saisi au login, gardé en mémoire uniquement le temps de l'écran, et `NewPw`). Aucune clé admin côté app.
- Succès → `POST /reset-status/ack` sur enroll, qui efface l'indicateur.
- Bouton « Plus tard » : l'écran est reproposé au prochain login tant que l'indicateur est actif.
- Sur TV, saisie au clavier de la télécommande : prévoir l'affichage du mot de passe (icône œil).

## 11. Recette

| Test | Android tél. | Shield | Windows | Mac |
|---|---|---|---|---|
| Reset auto (certificat du même utilisateur) : e-mail reçu + notif HA info | ☐ | ☐ | ☐ | ☐ |
| Reset via approbation HA (certificat d'un autre utilisateur) | ☐ | ☐ | ☐ | ☐ |
| Refus HA : aucun changement, aucun e-mail | ☐ | ☐ | ☐ | ☐ |
| Utilisateur sans e-mail : message neutre, notif HA info, aucun reset | ☐ | ☐ | ☐ | ☐ |
| Utilisateur inexistant : réponse strictement identique | ☐ | ☐ | ☐ | ☐ |
| Rate limit (2e demande < 1 h ; 6e par certificat / 24 h) : ignorée + notif HA | ☐ | ☐ | ☐ | ☐ |
| Expiration à 24 h : décision tardive refusée | ☐ | ☐ | ☐ | ☐ |
| Requête directe sur enroll hors Caddy (headers forgés ou absents) : refusée | ☐ | ☐ | ☐ | ☐ |
| E-mail reçu en français, sans lien, avec les consignes | ☐ | ☐ | ☐ | ☐ |
| Mot de passe temporaire fonctionnel sur Jellyfin web | ☐ | ☐ | ☐ | ☐ |
| Mot de passe temporaire fonctionnel dans OB Max | ☐ | ☐ | ☐ | ☐ |
| Textes FR corrects (lien, écran, messages) | ☐ | ☐ | ☐ | ☐ |
| Mot de passe absent des logs, du journal et de la notification HA | ☐ | ☐ | ☐ | ☐ |
| Aucun secret dans git (`git grep`, historique du commit) | ☐ | ☐ | ☐ | ☐ |
| Après login avec mot de passe temporaire : écran de changement proposé, nouveau mot de passe effectif, indicateur effacé | ☐ | ☐ | ☐ | ☐ |
| « Plus tard » : écran reproposé au login suivant | ☐ | ☐ | ☐ | ☐ |
| Page admin : accessible avec un certificat admin, 403 avec un certificat non admin | ☐ | — | ☐ | ☐ |
| Page admin : ajout/modif d'e-mail, approbation d'une demande, reset manuel, journal | ☐ | — | ☐ | ☐ |

## 12. Hors périmètre

- Demande depuis le web ou sans l'app OB Max.
- Autres canaux (WhatsApp, SMS).
- Changement de mot de passe obligatoire côté Jellyfin.
- 2FA.

## 13. Livrables

1. Code `obmax-enroll` : endpoints `/reset-request`, `/reset-decision`, `/reset-status` (+ `/ack`), page `/admin`, migration, journal, rate limit, expiration.
2. Hook OB Max (`lib/obmax/`) : lien « Mot de passe oublié ? », écran de changement après reset, clés `.arb` FR.
3. Config Caddy : diff présenté avant application.
4. YAML Home Assistant (automatisations + `rest_command`).
5. `OBMAX_CHANGES.md` et `TEST_CHECKLIST.md` à jour.
6. Doc courte d'exploitation : gérer les adresses e-mail, faire tourner les secrets (clé API Jellyfin, SMTP, webhook HA, secret de décision, secret Caddy→enroll), comportement vérifié de l'API Jellyfin.
7. Résumé final (ce qui a été fait, écarts, points à arbitrer restants).
