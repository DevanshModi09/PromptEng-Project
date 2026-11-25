#!/bin/bash
# CampusCrew – run this once on your EC2 instance
# Works on: Amazon Linux 2023, Ubuntu 22.04 / 24.04
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> Detecting OS..."
. /etc/os-release

echo "==> Installing nginx (skipped if already installed)..."
if [[ "$ID" == "ubuntu" || "$ID" == "debian" ]]; then
  sudo apt-get update -y -q
  sudo apt-get install -y -q nginx
else
  sudo yum install -y nginx 2>/dev/null || sudo dnf install -y nginx
fi

echo "==> Copying app to /var/www/campuscrew..."
sudo mkdir -p /var/www/campuscrew
sudo cp "$SCRIPT_DIR/index.html" /var/www/campuscrew/index.html
sudo chmod -R 755 /var/www/campuscrew

echo "==> Installing nginx config (non-destructive)..."
sudo cp "$SCRIPT_DIR/campuscrew.nginx.conf" /etc/nginx/conf.d/campuscrew.conf

echo "==> Testing nginx config..."
sudo nginx -t

echo "==> Reloading nginx..."
sudo systemctl enable nginx
sudo systemctl reload nginx || sudo systemctl start nginx

PUBLIC_IP=$(curl -s --max-time 3 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || hostname -I | awk '{print $1}')
echo ""
echo "======================================"
echo "  CampusCrew is live!"
echo "  Open: http://$PUBLIC_IP"
echo "======================================"
