#!/bin/sh
# OB Max V2, end of migration: Caddy only trusts the OB Max intermediate, so
# the old .p12 (signed by the root) stops working and revoking the
# intermediate becomes effective. Run on the NAS: sudo sh ./nas-finish-migration.sh
set -eu
VAR=/var/packages/caddy/var
BIN=/var/packages/caddy/target/bin/caddy
F=$VAR/Caddyfile
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP=$F.avant-fin-migration-$STAMP

if ! grep -q "trust_pool file $VAR/ca.crt $VAR/obmax-enroll-ca.crt" "$F"; then
  echo "Ligne trust_pool attendue introuvable, rien n'est modifié. Actuellement :" >&2
  grep -n trust_pool "$F" >&2 || true
  exit 1
fi

cp -p "$F" "$BACKUP"
echo "Sauvegarde : $BACKUP"
sed -i \
  -e "s#trust_pool file $VAR/ca.crt $VAR/obmax-enroll-ca.crt#trust_pool file $VAR/obmax-enroll-ca.crt#" \
  -e "s#\# OB Max V2, transition : racine (ancien .p12) + intermédiaire OB Max.#\# OB Max V2 : seule la CA intermédiaire OB Max est acceptée.#" \
  -e "/# Fin de migration : retirer/d" \
  "$F"
grep -n -B1 trust_pool "$F"

if "$BIN" validate --config "$F" --adapter caddyfile; then
  echo
  echo "Configuration valide. Redémarrage de Caddy..."
  /usr/syno/bin/synopkg restart caddy
  echo "OK."
  echo "Retour arrière si besoin :"
  echo "  sudo cp -p $BACKUP $F && sudo /usr/syno/bin/synopkg restart caddy"
else
  echo
  echo "Configuration REFUSÉE : l'ancien Caddyfile est restauré, rien n'a changé." >&2
  cp -p "$BACKUP" "$F"
  exit 1
fi
