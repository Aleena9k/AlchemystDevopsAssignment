#!/usr/bin/env bash
# =============================================================================
# gateway-vm startup script
# Installs nginx as a reverse proxy, forwards port 80/3111 to the iii engine
# This is the only VM with a public IP
# =============================================================================

set -euo pipefail

ENGINE_IP="${ENGINE_IP:-10.0.0.3}"   # update to engine-vm's internal IP

apt-get update -y
apt-get install -y nginx curl

# Configure nginx reverse proxy
cat > /etc/nginx/sites-available/alchemyst <<EOF
server {
    listen 3111;
    server_name _;

    location / {
        proxy_pass http://${ENGINE_IP}:3111;
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 300s;
        proxy_connect_timeout 10s;
    }
}
EOF

ln -sf /etc/nginx/sites-available/alchemyst /etc/nginx/sites-enabled/alchemyst
rm -f /etc/nginx/sites-enabled/default

nginx -t
systemctl enable nginx
systemctl restart nginx

echo "Gateway started. Forwarding :3111 -> ${ENGINE_IP}:3111"
