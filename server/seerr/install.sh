#!/bin/sh
# OB Max: installs or updates Seerr on this Pi. Run from this folder:
#   sudo sh ./install.sh
set -eu
cd "$(dirname "$0")"

if ss -ltn '( sport = :5055 )' | grep -q ':5055' && ! docker ps --format '{{.Names}}' | grep -qx seerr; then
  echo "Le port 5055 est déjà utilisé sur ce Pi : change-le dans docker-compose.yml." >&2
  exit 1
fi

# The container runs as the node user (UID 1000).
mkdir -p config
chown -R 1000:1000 config

docker compose pull
docker compose up -d
echo "Démarrage (jusqu'à une minute)..."
for i in $(seq 1 30); do
  if curl -fsS http://127.0.0.1:5055/api/v1/settings/public >/dev/null 2>&1; then
    echo "Seerr répond : http://$(hostname -I | awk '{print $1}'):5055"
    docker compose ps
    exit 0
  fi
  sleep 3
done
echo "Seerr ne répond pas encore. Voir : docker compose logs --tail 30" >&2
docker compose ps
exit 1
