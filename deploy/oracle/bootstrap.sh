#!/usr/bin/env bash
# Installs and starts FreeLLMAPI + DeepSeek Harness + cloudflared on an Ubuntu
# VM with no manual step. cloud-init.yaml runs it on the first boot, and the
# dsh-bootstrap systemd unit it installs runs it again on every boot. It is
# idempotent: existing secrets and volumes are kept.
#
# Settings come from /opt/dsh/settings.env (written by cloud-init):
#   ADMIN_EMAIL              first FreeLLMAPI account, and the only address
#                            allowed through the Quick Tunnels
#   DOMAIN                   empty: no domain, protected *.trycloudflare.com
#                            Quick Tunnels (new addresses on every boot);
#                            set: serves dsh.$DOMAIN and llm.$DOMAIN
#   CLOUDFLARE_TUNNEL_TOKEN  remote-managed tunnel token, only with DOMAIN
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
DOMAIN="${DOMAIN:-}"

[[ "${ADMIN_EMAIL:-}" =~ ^[^@[:space:]\"\\]+@[^@[:space:]\"\\]+\.[^@[:space:]\"\\]+$ ]] \
  || fail "ADMIN_EMAIL n'est pas une adresse e-mail valide dans $SETTINGS"
case "$ADMIN_EMAIL" in *@example.com) fail "ADMIN_EMAIL n'est pas rempli dans $SETTINGS" ;; esac

if [ -z "$DOMAIN" ]; then
  MODE=quick
else
  MODE=named
  case "$DOMAIN" in
    *mondomaine*|*' '*|http*|*/*) fail "DOMAIN doit être un nom de domaine seul (ex. mondomaine.com) dans $SETTINGS" ;;
  esac
  case "${CLOUDFLARE_TUNNEL_TOKEN:-}" in
    ''|*COLLE*) fail "avec un DOMAIN, CLOUDFLARE_TUNNEL_TOKEN doit être rempli dans $SETTINGS" ;;
  esac
fi
log "mode: $MODE"

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
write_env() { # write_env <dsh public host>
  cat > "$DSH_DIR/.env" <<EOF
COMPOSE_PROFILES=$MODE
DSH_PUBLIC_HOST=$1
ADMIN_EMAIL=$ADMIN_EMAIL
CLOUDFLARE_TUNNEL_TOKEN=${CLOUDFLARE_TUNNEL_TOKEN:-}
EOF
}
if [ "$MODE" = named ]; then write_env "dsh.$DOMAIN"; else write_env pending.invalid; fi

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
compose up -d --remove-orphans freellmapi
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

quick_url() { # quick_url <service>: the trycloudflare address the tunnel announced
  compose logs "$1" 2>/dev/null | grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' | tail -1 || true
}

if [ "$MODE" = quick ]; then
  log "ouverture des tunnels protégés (trycloudflare)"
  compose up -d --force-recreate quick-dsh quick-llm
  DSH_URL="" LLM_URL=""
  for _ in $(seq 1 40); do
    DSH_URL="$(quick_url quick-dsh)"; LLM_URL="$(quick_url quick-llm)"
    [ -n "$DSH_URL" ] && [ -n "$LLM_URL" ] && break
    sleep 3
  done
  [ -n "$DSH_URL" ] && [ -n "$LLM_URL" ] || fail "les tunnels Cloudflare ne s'ouvrent pas (docker compose logs quick-dsh)"
  write_env "${DSH_URL#https://}"
  LLM_PUBLIC="$LLM_URL"
  log "démarrage du harness"
  # Recreate dsh so the new tunnel host, a regenerated key or a newer image is picked up.
  compose up -d --force-recreate dsh
else
  LLM_PUBLIC="https://llm.$DOMAIN"
  log "démarrage du harness et du tunnel"
  compose up -d --force-recreate dsh cloudflared
fi

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
Description=DeepSeek Harness bootstrap (FreeLLMAPI key sync, tunnels, launch URL)
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
 FreeLLMAPI  : $LLM_PUBLIC
EOF
if [ -n "$FIRST_ADMIN" ]; then
  cat <<EOF
   compte    : $ADMIN_EMAIL
   mot de passe (à changer dans Settings) : $FIRST_ADMIN
EOF
fi
cat <<EOF

 Accès réservé à $ADMIN_EMAIL (code envoyé par e-mail).
EOF
if [ "$MODE" = quick ]; then
  cat <<EOF
 Ces adresses changent à chaque redémarrage du serveur.
EOF
fi
cat <<EOF
 Le lien du harness contient un jeton : ne le partage pas.
==================================================================
EOF
