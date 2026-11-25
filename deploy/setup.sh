#!/bin/bash
# CampusCrew – one-shot EC2 setup script
# Run as: bash setup.sh
# Tested on: Amazon Linux 2023 / Ubuntu 22.04 / 24.04
set -e

echo "==> Detecting OS..."
if [ -f /etc/os-release ]; then
  . /etc/os-release
  OS=$ID
else
  echo "Cannot detect OS. Exiting."; exit 1
fi

echo "==> Installing nginx..."
if [[ "$OS" == "ubuntu" || "$OS" == "debian" ]]; then
  sudo apt-get update -y
  sudo apt-get install -y nginx
elif [[ "$OS" == "amzn" || "$OS" == "centos" || "$OS" == "rhel" ]]; then
  sudo yum install -y nginx || sudo dnf install -y nginx
else
  echo "Unsupported OS: $OS. Install nginx manually."; exit 1
fi

echo "==> Copying app files..."
sudo mkdir -p /var/www/campuscrew
sudo cp ../campuscrew_demo.html /var/www/campuscrew/index.html
sudo chmod -R 755 /var/www/campuscrew

echo "==> Installing nginx config..."
# Drops a new server block into conf.d — does NOT touch your existing nginx.conf
# or any other site/SSL config already on this machine.
sudo cp campuscrew.nginx.conf /etc/nginx/conf.d/campuscrew.conf

echo "==> Testing nginx config..."
sudo nginx -t

echo "==> Reloading nginx (keeps existing config + certs live)..."
sudo systemctl reload nginx

echo ""
echo "======================================"
echo "  Done! CampusCrew is live."
echo "  Open http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || hostname -I | awk '{print $1}') in your browser."
echo "======================================"
