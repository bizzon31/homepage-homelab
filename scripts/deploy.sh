#!/usr/bin/env bash
# Деплой конфигурации Homepage на S2 LXC 1013
set -euo pipefail

REMOTE="root@77.51.218.207"
SSH_PORT=42222
LXC=1013
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

CONFIG_FILES=(
  services.yaml
  settings.yaml
  widgets.yaml
  custom.css
  docker.yaml
  bookmarks.yaml
)

echo "==> Конфиг Homepage -> LXC $LXC (192.168.10.22)"

for f in "${CONFIG_FILES[@]}"; do
  scp -P "$SSH_PORT" "$ROOT/config/$f" "$REMOTE:/tmp/homepage-$f"
  ssh -p "$SSH_PORT" "$REMOTE" "pct push $LXC /tmp/homepage-$f /opt/homepage/config/$f"
done

scp -P "$SSH_PORT" "$ROOT/docker-compose.yml" "$REMOTE:/tmp/homepage-docker-compose.yml"
ssh -p "$SSH_PORT" "$REMOTE" "pct push $LXC /tmp/homepage-docker-compose.yml /opt/homepage/docker-compose.yml"

ssh -p "$SSH_PORT" "$REMOTE" "pct exec $LXC -- bash -c 'cd /opt/homepage && docker-compose up -d'"

echo "==> Готово. Проверка: https://homepage.bizzon8n.ru"
