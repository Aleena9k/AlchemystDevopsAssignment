#!/usr/bin/env bash
# =============================================================================
# engine-vm startup script
# Installs and starts the iii engine as a systemd service
# =============================================================================

set -euo pipefail

ENGINE_PORT=49134
HTTP_PORT=3111

apt-get update -y
apt-get install -y curl jq

# Install iii engine
curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
export PATH="/usr/local/bin:$HOME/.local/bin:$PATH"

# Write systemd service
cat > /etc/systemd/system/iii-engine.service <<EOF
[Unit]
Description=iii RPC Engine
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/alchemyst
ExecStart=/root/.local/bin/iii --use-default-config
Restart=always
RestartSec=5
Environment=PATH=/root/.local/bin:/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=multi-user.target
EOF

mkdir -p /opt/alchemyst

systemctl daemon-reload
systemctl enable iii-engine
systemctl start iii-engine

echo "iii engine started on ws://$(hostname -I | awk '{print $1}'):${ENGINE_PORT}"
echo "HTTP API available on http://$(hostname -I | awk '{print $1}'):${HTTP_PORT}"
