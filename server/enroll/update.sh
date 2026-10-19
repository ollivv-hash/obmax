#!/bin/sh
# OB Max: updates obmax-enroll on this Pi without touching data/ (CA, devices).
# Run from ~/obmax-enroll-update: sudo sh ./update.sh
set -eu
cd "$(dirname "$0")"
TARGET="$HOME/obmax-enroll"
[ -n "${SUDO_USER:-}" ] && TARGET="$(getent passwd "$SUDO_USER" | cut -d: -f6)/obmax-enroll"
if [ ! -f "$TARGET/data/ca/obmax-enroll-ca.key" ]; then
  echo "Service introuvable dans $TARGET (data/ca manquant) : rien n'est modifié." >&2
  exit 1
fi
STAMP=$(date +%Y%m%d-%H%M%S)
tar -C "$TARGET" --exclude=./data -czf "$TARGET/../obmax-enroll-code-avant-$STAMP.tgz" .
echo "Sauvegarde du code : $(dirname "$TARGET")/obmax-enroll-code-avant-$STAMP.tgz"
# PUBLIC_SERVER_URL moved from docker-compose.yml to .env: keep the value.
if [ ! -f "$TARGET/.env" ]; then
  url=$(sed -n 's/^ *PUBLIC_SERVER_URL: *\(https:[^ ]*\).*/\1/p' "$TARGET/docker-compose.yml" | head -n 1)
  if [ -z "$url" ]; then
    echo "PUBLIC_SERVER_URL introuvable : crée $TARGET/.env (PUBLIC_SERVER_URL=https://...) puis relance." >&2
    exit 1
  fi
  printf 'PUBLIC_SERVER_URL=%s\n' "$url" > "$TARGET/.env"
  echo "Créé : $TARGET/.env"
fi
for f in *.go go.mod Dockerfile docker-compose.yml README.md; do cp -f "$f" "$TARGET/"; done
rm -rf "$TARGET/web" && cp -R web "$TARGET/web"
cd "$TARGET"
docker compose up -d --build
echo "Démarrage..."
sleep 5
docker compose ps
docker compose logs --tail 3
printf 'Santé : '
curl -fsS http://127.0.0.1:8787/v1/health && echo || echo "ÉCHEC (voir docker compose logs)"
