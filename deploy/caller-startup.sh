#!/usr/bin/env bash
# =============================================================================
# caller-vm startup script  
# Installs Node.js, starts the TypeScript caller worker
# Connects back to the iii engine running on engine-vm
# =============================================================================

set -euo pipefail

ENGINE_IP="${ENGINE_IP:-10.0.0.3}"   # update to engine-vm's internal IP
ENGINE_URL="ws://${ENGINE_IP}:49134"

apt-get update -y
apt-get install -y git curl

# Install Node.js 20
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# Clone the repo
git clone https://github.com/Alchemyst-ai/hiring.git /opt/alchemyst
cd /opt/alchemyst/may-2026/devops/quickstart/workers/caller-worker

# Install npm dependencies
npm install

# Write systemd service
cat > /etc/systemd/system/caller-worker.service <<EOF
[Unit]
Description=Alchemyst Caller Worker
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/alchemyst/may-2026/devops/quickstart/workers/caller-worker
ExecStart=/usr/bin/npm run dev
Restart=always
RestartSec=5
Environment=III_URL=${ENGINE_URL}
Environment=PATH=/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable caller-worker
systemctl start caller-worker

echo "Caller worker started, connected to engine at ${ENGINE_URL}"
