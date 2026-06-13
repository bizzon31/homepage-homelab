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

scp -P "$SSH_PORT" -r "$ROOT/sensors/"* "$REMOTE:/tmp/homepage-sensors/"
ssh -p "$SSH_PORT" "$REMOTE" "pct push $LXC /tmp/homepage-sensors/collect_and_serve.py /opt/homepage/sensors/collect_and_serve.py"
ssh -p "$SSH_PORT" "$REMOTE" "pct push $LXC /tmp/homepage-sensors/homepage-sensors.service /opt/homepage/sensors/homepage-sensors.service"

ssh -p "$SSH_PORT" "$REMOTE" "pct exec $LXC -- bash -c '
  install -m 644 /opt/homepage/sensors/homepage-sensors.service /etc/systemd/system/homepage-sensors.service
  systemctl daemon-reload
  systemctl enable homepage-sensors.service
  systemctl restart homepage-sensors.service
  cd /opt/homepage && docker-compose up -d
  docker-compose restart homepage 2>/dev/null || true
'"

echo "==> Проверка sensors API"
ssh -p "$SSH_PORT" "$REMOTE" "pct exec $LXC -- curl -fsS http://127.0.0.1:3080/sensors.json | head -c 400"
echo ""

echo "==> Готово. Проверка: https://homepage.bizzon8n.ru"
