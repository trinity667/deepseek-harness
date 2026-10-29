#!/usr/bin/env bash
# One-time setup of an Oracle Cloud Always Free Ubuntu 24.04 VM (Ampere A1,
# arm64) for DeepSeek Harness + FreeLLMAPI + Cloudflare Tunnel.
# Run as the default `ubuntu` user:  bash setup-vm.sh
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/trinity667/deepseek-harness.git}"
APP_DIR="${APP_DIR:-$HOME/deepseek-harness}"

echo "==> Docker (Ubuntu packages)"
sudo apt-get update
sudo apt-get install -y docker.io docker-compose-v2 docker-buildx git openssl
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"

echo "==> 4 GB swap, so the build survives memory peaks"
if ! swapon --show | grep -q /swapfile; then
  sudo fallocate -l 4G /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
fi

echo "==> Repository"
if [ ! -d "$APP_DIR/.git" ]; then
  git clone "$REPO_URL" "$APP_DIR"
fi
cd "$APP_DIR"

ENV_FILE=deploy/oracle/.env
if [ ! -f "$ENV_FILE" ]; then
  cp deploy/oracle/.env.example "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  sed -i "s/^ENCRYPTION_KEY=.*/ENCRYPTION_KEY=$(openssl rand -hex 32)/" "$ENV_FILE"
  echo "Created $ENV_FILE with a fresh ENCRYPTION_KEY."
fi

cat <<EOF

Done. Next steps (see deploy/oracle/README.md):
  1. Log out and back in (docker group), then: cd $APP_DIR
  2. Fill DSH_PUBLIC_HOST and CLOUDFLARE_TUNNEL_TOKEN in $ENV_FILE
  3. docker compose -f deploy/oracle/compose.yml up -d freellmapi
  4. Configure FreeLLMAPI through an SSH tunnel, copy its API key into FREE_LLM_API_KEY
  5. DSH_COMMIT=\$(git rev-parse HEAD) docker compose -f deploy/oracle/compose.yml up -d --build
EOF
