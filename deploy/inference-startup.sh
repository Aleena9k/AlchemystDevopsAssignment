#!/usr/bin/env bash
# =============================================================================
# inference-vm startup script
# Installs Python deps, downloads Gemma model, starts inference worker
# Connects back to the iii engine running on engine-vm
# =============================================================================

set -euo pipefail

# Engine internal IP — passed as instance metadata or hardcoded after setup
ENGINE_IP="${ENGINE_IP:-10.0.0.3}"   # update to engine-vm's internal IP
ENGINE_URL="ws://${ENGINE_IP}:49134"

apt-get update -y
apt-get install -y python3 python3-pip python3-venv git curl

# Clone the repo
git clone https://github.com/Alchemyst-ai/hiring.git /opt/alchemyst
cd /opt/alchemyst/may-2026/devops/quickstart/workers/inference-worker

# Create virtualenv and install dependencies
python3 -m venv /opt/venv
source /opt/venv/bin/activate
pip install --upgrade pip
pip install iii-sdk watchfiles transformers accelerate gguf
pip install torch --index-url https://download.pytorch.org/whl/cpu

# Write systemd service
cat > /etc/systemd/system/inference-worker.service <<EOF
[Unit]
Description=Alchemyst Inference Worker
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/alchemyst/may-2026/devops/quickstart/workers/inference-worker
ExecStart=/opt/venv/bin/python3 inference_worker.py
Restart=always
RestartSec=10
Environment=III_URL=${ENGINE_URL}
Environment=PATH=/opt/venv/bin:/usr/local/bin:/usr/bin:/bin

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable inference-worker
systemctl start inference-worker

echo "Inference worker started, connected to engine at ${ENGINE_URL}"
