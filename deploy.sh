#!/bin/bash
# ============================================================
#  CampusCrew – one-shot EC2 deploy script
#  Usage: bash deploy.sh
#  Tested on: Ubuntu 22.04/24.04 · Amazon Linux 2023
#
#  What it does (fully automated):
#    1. Detects OS and installs Docker + Docker Compose
#    2. Stops & removes any old container/image
#    3. Builds the Docker image (nginx + Node backend + SQLite)
#    4. Starts the container on port 80
#    5. Configures firewall to allow port 80
#    6. Prints the public URL
# ============================================================
set -euo pipefail

# ── Colour helpers ────────────────────────────────────────────
GREEN="\033[0;32m"; YELLOW="\033[1;33m"; RED="\033[0;31m"; NC="\033[0m"
info()  { echo -e "${GREEN}==>${NC} $*"; }
warn()  { echo -e "${YELLOW}  ! $*${NC}"; }
fatal() { echo -e "${RED}ERROR: $*${NC}"; exit 1; }

# ── Must run from repo root (where deploy.sh lives) ──────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"
[[ -f "campuscrew_demo.html" ]] || fatal "Run this script from the CampusCrew repo root."

# ── OS detection ─────────────────────────────────────────────
info "Detecting OS..."
OS_ID=""
[[ -f /etc/os-release ]] && . /etc/os-release && OS_ID="$ID"
[[ -z "$OS_ID" ]] && fatal "Cannot detect OS."

# ── Install Docker if not present ────────────────────────────
if ! command -v docker &>/dev/null; then
  info "Installing Docker..."
  if [[ "$OS_ID" == "ubuntu" || "$OS_ID" == "debian" ]]; then
    sudo apt-get update -y -qq
    sudo apt-get install -y -qq ca-certificates curl gnupg lsb-release
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/${OS_ID}/gpg \
      | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
      https://download.docker.com/linux/${OS_ID} $(lsb_release -cs) stable" \
      | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    sudo apt-get update -y -qq
    sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-compose-plugin
  elif [[ "$OS_ID" == "amzn" ]]; then
    sudo yum install -y docker
    sudo systemctl enable --now docker
  else
    fatal "Unsupported OS: $OS_ID. Install Docker manually: https://docs.docker.com/engine/install/"
  fi
  sudo usermod -aG docker "$USER" 2>/dev/null || true
  info "Docker installed."
else
  info "Docker already installed: $(docker --version)"
fi

# Ensure Docker daemon is running
sudo systemctl enable --now docker 2>/dev/null || true

# ── Install docker compose (v2 plugin) if needed ─────────────
if ! docker compose version &>/dev/null 2>&1; then
  info "Installing Docker Compose plugin..."
  if [[ "$OS_ID" == "ubuntu" || "$OS_ID" == "debian" ]]; then
    sudo apt-get install -y -qq docker-compose-plugin
  elif [[ "$OS_ID" == "amzn" ]]; then
    sudo curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m)" \
      -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose
    # Create shim so "docker compose" works
    mkdir -p ~/.docker/cli-plugins
    ln -sf /usr/local/bin/docker-compose ~/.docker/cli-plugins/docker-compose 2>/dev/null || true
  fi
fi

# ── Open port 80 in OS firewall ───────────────────────────────
info "Configuring firewall..."
if command -v ufw &>/dev/null; then
  sudo ufw allow 80/tcp >/dev/null 2>&1 || true
  sudo ufw allow 443/tcp >/dev/null 2>&1 || true
elif command -v firewall-cmd &>/dev/null; then
  sudo firewall-cmd --permanent --add-port=80/tcp >/dev/null 2>&1 || true
  sudo firewall-cmd --permanent --add-port=443/tcp >/dev/null 2>&1 || true
  sudo firewall-cmd --reload >/dev/null 2>&1 || true
elif command -v iptables &>/dev/null; then
  sudo iptables -I INPUT -p tcp --dport 80 -j ACCEPT 2>/dev/null || true
fi

# ── Install nginx if not present ─────────────────────────────
if ! command -v nginx &>/dev/null; then
  info "Installing nginx..."
  if [[ "$OS_ID" == "ubuntu" || "$OS_ID" == "debian" ]]; then
    sudo apt-get install -y -qq nginx
  elif [[ "$OS_ID" == "amzn" ]]; then
    sudo yum install -y nginx || sudo dnf install -y nginx
  fi
  sudo systemctl enable nginx
fi

# ── Configure nginx (HTTP first, HTTPS after cert) ───────────
info "Configuring nginx..."
sudo tee /etc/nginx/sites-enabled/default > /dev/null <<NGINX
server {
    listen 80;
    server_name _;

    # Needed for certbot webroot challenge
    location /.well-known/acme-challenge/ { root /var/www/html; }

    location / {
        proxy_pass         http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
    }
}
NGINX
sudo mkdir -p /var/www/html
sudo nginx -t && sudo systemctl reload nginx || sudo systemctl start nginx

# ── Certbot HTTPS on raw IP ───────────────────────────────────
PUBLIC_IP=$(curl -s --max-time 3 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null \
            || curl -s --max-time 3 https://checkip.amazonaws.com 2>/dev/null \
            || hostname -I | awk '{print $1}')

CERT_PATH="/etc/letsencrypt/live/${PUBLIC_IP}/fullchain.pem"

if [[ ! -f "$CERT_PATH" ]]; then
  info "Installing certbot and getting SSL cert for ${PUBLIC_IP}..."
  sudo snap install --classic certbot 2>/dev/null || true
  sudo ln -sf /snap/bin/certbot /usr/local/bin/certbot 2>/dev/null || true

  sudo certbot certonly \
    --preferred-profile shortlived \
    --webroot --webroot-path /var/www/html \
    --ip-address "${PUBLIC_IP}" \
    --non-interactive --agree-tos --register-unsafely-without-email \
    && info "SSL cert obtained!" || warn "Certbot failed – continuing with HTTP only."
else
  info "SSL cert already exists for ${PUBLIC_IP}, skipping certbot."
fi

# ── Update nginx with HTTPS if cert exists ────────────────────
if [[ -f "$CERT_PATH" ]]; then
  info "Enabling HTTPS in nginx..."
  sudo tee /etc/nginx/sites-enabled/default > /dev/null <<NGINX
server {
    listen 80;
    location /.well-known/acme-challenge/ { root /var/www/html; }
    location / { return 301 https://\$host\$request_uri; }
}

server {
    listen 443 ssl;
    ssl_certificate     /etc/letsencrypt/live/${PUBLIC_IP}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${PUBLIC_IP}/privkey.pem;

    location / {
        proxy_pass         http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
    }
}
NGINX
  # Auto-renew hook so nginx reloads after cert renewal
  echo '#!/bin/sh
systemctl reload nginx' | sudo tee /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh > /dev/null
  sudo chmod +x /etc/letsencrypt/renewal-hooks/deploy/reload-nginx.sh
  sudo nginx -t && sudo systemctl reload nginx
fi

# ── Remove any old CampusCrew container / image ──────────────
info "Cleaning up old deployment (if any)..."
docker compose down --remove-orphans 2>/dev/null || true
docker rm -f campuscrew 2>/dev/null || true
# Note: we do NOT remove the named volume (campuscrew_data) so the DB is preserved on updates.

# ── Build + start ─────────────────────────────────────────────
info "Building Docker image (this takes ~60s on first run)..."
docker compose build --pull --no-cache

info "Starting CampusCrew..."
docker compose up -d

# ── Health check ──────────────────────────────────────────────
info "Waiting for health check..."
ATTEMPTS=0
until curl -sf http://localhost/api/health &>/dev/null; do
  ATTEMPTS=$((ATTEMPTS+1))
  [[ $ATTEMPTS -ge 20 ]] && fatal "Health check failed after 20 attempts. Run: docker logs campuscrew"
  sleep 3
done

# ── Print URL ─────────────────────────────────────────────────
PROTO="http"
[[ -f "$CERT_PATH" ]] && PROTO="https"

echo ""
echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}  CampusCrew is live!${NC}"
echo -e "${GREEN}  Frontend : ${PROTO}://${PUBLIC_IP}${NC}"
echo -e "${GREEN}  API      : ${PROTO}://${PUBLIC_IP}/api/services${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo ""
echo "  Useful commands:"
echo "    docker logs -f campuscrew        # live logs"
echo "    docker compose down              # stop"
echo "    bash deploy.sh                   # redeploy after git pull"
echo ""
