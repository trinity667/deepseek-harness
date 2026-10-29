#!/usr/bin/env bash
# Installs and starts FreeLLMAPI + DeepSeek Harness + cloudflared on an Ubuntu
# VM with no manual step. cloud-init.yaml runs it on the first boot, and the
# dsh-bootstrap systemd unit it installs runs it again on every boot. It is
# idempotent: existing secrets and volumes are kept.
#
# Settings come from /opt/dsh/settings.env (written by cloud-init):
#   DOMAIN                   Cloudflare zone; serves dsh.$DOMAIN and llm.$DOMAIN
#   ADMIN_EMAIL              first FreeLLMAPI dashboard account
#   CLOUDFLARE_TUNNEL_TOKEN  remote-managed tunnel token
#   REF                      optional git ref of this repository (default master)
#
# For tests, DSH_SOURCE_DIR=<checkout>/deploy/oracle copies the files from a
# checkout instead of downloading them, and DSH_DIR moves the install root.
set -euo pipefail

DSH_DIR="${DSH_DIR:-/opt/dsh}"
SETTINGS="${SETTINGS:-$DSH_DIR/settings.env}"
REPO_RAW="https://raw.githubusercontent.com/trinity667/deepseek-harness"

log() { printf '[dsh-bootstrap] %s\n' "$*"; }
fail() { log "ERREUR: $*"; exit 1; }

[ -f "$SETTINGS" ] || fail "fichier de réglages absent: $SETTINGS"
# shellcheck disable=SC1090
. "$SETTINGS"
REF="${REF:-master}"

case "${DOMAIN:-}" in
  ''|*mondomaine*|*' '*) fail "DOMAIN n'est pas rempli dans $SETTINGS" ;;
esac
[[ "${ADMIN_EMAIL:-}" =~ ^[^@[:space:]\"\\]+@[^@[:space:]\"\\]+\.[^@[:space:]\"\\]+$ ]] \
  || fail "ADMIN_EMAIL n'est pas une adresse e-mail valide dans $SETTINGS"
case "${CLOUDFLARE_TUNNEL_TOKEN:-}" in
  ''|*COLLE*) fail "CLOUDFLARE_TUNNEL_TOKEN n'est pas rempli dans $SETTINGS" ;;
esac

if ! command -v docker >/dev/null 2>&1 || ! docker compose version >/dev/null 2>&1; then
  log "installation de Docker"
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io docker-compose-v2 openssl curl
  systemctl enable --now docker
fi

log "fichiers de déploiement (ref $REF)"
mkdir -p "$DSH_DIR/dsh"
for file in compose.yml dsh/freellmapi.patch.yml bootstrap.sh; do
  if [ -n "${DSH_SOURCE_DIR:-}" ]; then
    cp "$DSH_SOURCE_DIR/$file" "$DSH_DIR/$file.new"
  else
    curl -fsSL "$REPO_RAW/$REF/deploy/oracle/$file" -o "$DSH_DIR/$file.new"
  fi
  mv "$DSH_DIR/$file.new" "$DSH_DIR/$file"
done
chmod 755 "$DSH_DIR/bootstrap.sh"

umask 077
cat > "$DSH_DIR/.env" <<EOF
DSH_PUBLIC_HOST=dsh.$DOMAIN
CLOUDFLARE_TUNNEL_TOKEN=$CLOUDFLARE_TUNNEL_TOKEN
EOF

FIRST_ADMIN=""
if [ ! -f "$DSH_DIR/freellmapi.env" ]; then
  FIRST_ADMIN="$(openssl rand -hex 12)"
  cat > "$DSH_DIR/freellmapi.env" <<EOF
ENCRYPTION_KEY=$(openssl rand -hex 32)
FREEAPI_CONFIG_JSON={"admin":{"email":"$ADMIN_EMAIL","password":"$FIRST_ADMIN"}}
EOF
fi
touch "$DSH_DIR/dsh.env"

compose() { docker compose --project-directory "$DSH_DIR" -f "$DSH_DIR/compose.yml" "$@"; }

log "démarrage de FreeLLMAPI"
compose pull --quiet
compose up -d freellmapi
for _ in $(seq 1 60); do
  [ "$(docker inspect -f '{{.State.Health.Status}}' "$(compose ps -q freellmapi)")" = healthy ] && break
  sleep 5
done
[ "$(docker inspect -f '{{.State.Health.Status}}' "$(compose ps -q freellmapi)")" = healthy ] \
  || fail "FreeLLMAPI ne démarre pas (docker compose logs freellmapi)"

# The admin account exists now; drop its plaintext password from the env file.
sed -i '/^FREEAPI_CONFIG_JSON=/d' "$DSH_DIR/freellmapi.env"

log "clé unifiée FreeLLMAPI -> dsh.env"
KEY="$(compose exec -T freellmapi node -e "
const db = require('better-sqlite3')('/app/server/data/freeapi.db', { readonly: true });
process.stdout.write(db.prepare(\"SELECT value FROM settings WHERE key = 'unified_api_key'\").get().value);
")"
[[ "$KEY" =~ ^freellmapi-[A-Za-z0-9_-]{16,}$ ]] || fail "clé unifiée illisible"
printf 'FREE_LLM_API_KEY=%s\n' "$KEY" > "$DSH_DIR/dsh.env"

log "démarrage du harness et du tunnel"
# Recreate dsh so a regenerated key or a newer image is picked up.
compose up -d --force-recreate dsh cloudflared

URL=""
for _ in $(seq 1 60); do
  URL="$(compose logs dsh 2>/dev/null | grep -o 'https://[^ ]*?token=[A-Za-z0-9_-]*' | tail -1 || true)"
  [ -n "$URL" ] && break
  sleep 3
done
[ -n "$URL" ] || fail "le harness ne démarre pas (docker compose logs dsh)"

if command -v systemctl >/dev/null 2>&1 && [ -d /etc/systemd/system ] && [ -z "${DSH_SOURCE_DIR:-}" ]; then
  cat > /etc/systemd/system/dsh-bootstrap.service <<EOF
[Unit]
Description=DeepSeek Harness bootstrap (FreeLLMAPI key sync, launch URL)
After=docker.service network-online.target
Wants=network-online.target
Requires=docker.service

[Service]
Type=oneshot
ExecStart=$DSH_DIR/bootstrap.sh
StandardOutput=journal+console

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable dsh-bootstrap.service >/dev/null 2>&1
fi

cat <<EOF

==================================================================
 DeepSeek Harness est prêt.

 Harness     : $URL
 FreeLLMAPI  : https://llm.$DOMAIN
EOF
if [ -n "$FIRST_ADMIN" ]; then
  cat <<EOF
   compte    : $ADMIN_EMAIL
   mot de passe (à changer dans Settings) : $FIRST_ADMIN
EOF
fi
cat <<EOF

 Le lien du harness contient un jeton valable jusqu'au prochain
 redémarrage. Ne le partage pas.
==================================================================
EOF
