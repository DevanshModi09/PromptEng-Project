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
until docker compose exec campuscrew wget -qO- http://localhost/api/health &>/dev/null; do
  ATTEMPTS=$((ATTEMPTS+1))
  [[ $ATTEMPTS -ge 20 ]] && fatal "Health check failed after 20 attempts. Run: docker logs campuscrew"
  sleep 3
done

# ── Print URL ─────────────────────────────────────────────────
PUBLIC_IP=$(curl -s --max-time 3 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null \
            || curl -s --max-time 3 https://checkip.amazonaws.com 2>/dev/null \
            || hostname -I | awk '{print $1}')

echo ""
echo -e "${GREEN}=====================================================${NC}"
echo -e "${GREEN}  CampusCrew is live!${NC}"
echo -e "${GREEN}  Frontend : http://${PUBLIC_IP}${NC}"
echo -e "${GREEN}  API      : http://${PUBLIC_IP}/api/services${NC}"
echo -e "${GREEN}=====================================================${NC}"
echo ""
echo "  Useful commands:"
echo "    docker logs -f campuscrew        # live logs"
echo "    docker compose down              # stop"
echo "    bash deploy.sh                   # redeploy after git pull"
echo ""
