#!/usr/bin/env bash
# Настройка SSH-ключа для сбора sensors с LXC 1013 (Homepage)
set -euo pipefail

REMOTE="root@77.51.218.207"
SSH_PORT=42222
LXC=1013
LXC_IP="192.168.10.22"
KEY_DIR="/opt/homepage/sensors/ssh"
KEY_COMMENT="homepage-sensors@1013"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> Деплой sensors на LXC $LXC"
ssh -p "$SSH_PORT" "$REMOTE" "pct exec $LXC -- mkdir -p $KEY_DIR /opt/homepage/sensors/data"
scp -P "$SSH_PORT" -r "$ROOT/sensors/"* "$REMOTE:/tmp/homepage-sensors/"
ssh -p "$SSH_PORT" "$REMOTE" "pct push $LXC /tmp/homepage-sensors/collect_and_serve.py /opt/homepage/sensors/collect_and_serve.py"

echo "==> SSH-ключ на LXC $LXC"
ssh -p "$SSH_PORT" "$REMOTE" "pct exec $LXC -- bash -s" <<EOF
set -euo pipefail
KEY_DIR="$KEY_DIR"
if [[ ! -f "\$KEY_DIR/id_ed25519" ]]; then
  mkdir -p "\$KEY_DIR"
  chmod 700 "\$KEY_DIR"
  ssh-keygen -t ed25519 -N "" -f "\$KEY_DIR/id_ed25519" -C "$KEY_COMMENT"
  chmod 600 "\$KEY_DIR/id_ed25519"
  chmod 644 "\$KEY_DIR/id_ed25519.pub"
fi
cat "\$KEY_DIR/id_ed25519.pub"
EOF

PUBKEY="$(ssh -p "$SSH_PORT" "$REMOTE" "pct exec $LXC -- cat $KEY_DIR/id_ed25519.pub")"
AUTH_LINE="from=\"$LXC_IP\",command=\"/usr/bin/sensors -j\",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty $PUBKEY"

echo "==> Добавление ключа на PVE-хосты"
for target in s1 s2 llm-pc; do
  case "$target" in
    s1)
      ssh s1 "grep -Fq '$KEY_COMMENT' /etc/pve/priv/authorized_keys 2>/dev/null || echo '$AUTH_LINE' >> /etc/pve/priv/authorized_keys"
      echo "  S1 (.10) OK"
      ;;
    s2)
      ssh -p "$SSH_PORT" "$REMOTE" "grep -Fq '$KEY_COMMENT' /root/.ssh/authorized_keys 2>/dev/null || echo '$AUTH_LINE' >> /root/.ssh/authorized_keys"
      echo "  S2 (.11) OK"
      ;;
    llm-pc)
      ssh s1 "ssh -o ConnectTimeout=5 root@192.168.10.70 bash -s" <<REMOTE
set -euo pipefail
sed -i '/homepage-sensors@1013/d' /etc/pve/priv/authorized_keys
grep -Fq '$KEY_COMMENT' /etc/pve/priv/authorized_keys 2>/dev/null || echo '$AUTH_LINE' >> /etc/pve/priv/authorized_keys
REMOTE
      echo "  LLM-PC (.70) OK"
      ;;
  esac
done

echo "==> Проверка SSH с LXC"
ssh -p "$SSH_PORT" "$REMOTE" "pct exec $LXC -- ssh -i $KEY_DIR/id_ed25519 -o BatchMode=yes -o ConnectTimeout=8 -o StrictHostKeyChecking=accept-new root@192.168.10.10 sensors -j | head -c 120"
echo ""
echo "==> Готово. Запустите deploy.sh для сборки контейнера."
