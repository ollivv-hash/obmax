#!/bin/sh
# OB Max: installs Caddy on this Pi. Run from this folder: sudo sh ./install.sh
set -eu
cd "$(dirname "$0")"

for port in 80 443; do
  if ss -ltn "( sport = :$port )" | grep -q ":$port " && ! docker ps --format '{{.Names}}' | grep -qx caddy; then
    echo "Le port $port est déjà utilisé sur ce Pi :" >&2
    ss -ltnp "( sport = :$port )" >&2
    exit 1
  fi
done
[ -f ca/obmax-enroll-ca.crt ] || { echo "ca/obmax-enroll-ca.crt manquant" >&2; exit 1; }

mkdir -p data config
docker compose pull
docker run --rm -v "$PWD/Caddyfile:/etc/caddy/Caddyfile:ro" -v "$PWD/ca:/etc/caddy/ca:ro" \
  caddy:2.11 caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
docker compose up -d
sleep 3
docker compose ps
echo
echo "Caddy tourne. Les certificats Let's Encrypt seront obtenus dès que la box"
echo "redirigera les ports 80 et 443 vers ce Pi (puis : sudo docker compose restart)."
