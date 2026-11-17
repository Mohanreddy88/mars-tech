#!/bin/bash
# One-time setup for a fresh Hostinger VPS (Ubuntu 22.04/24.04). Run as root:
#   curl -fsSL https://raw.githubusercontent.com/Mohanreddy88/mars-tech/main/deploy/setup-vps.sh | bash
# or, after cloning:  bash deploy/setup-vps.sh
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/Mohanreddy88/mars-tech.git}"
APP_DIR="${APP_DIR:-/opt/hrms}"

echo "==> Updating system"
export DEBIAN_FRONTEND=noninteractive
apt-get update -y && apt-get upgrade -y
apt-get install -y ca-certificates curl git ufw openssl

echo "==> Installing Docker"
if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com | sh
fi
systemctl enable --now docker

echo "==> Firewall (SSH, HTTP, HTTPS only)"
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 443/udp
ufw --force enable

echo "==> Swap (helps the Angular build)"
if ! swapon --show | grep -q /swapfile; then
  fallocate -l 4G /swapfile && chmod 600 /swapfile && mkswap /swapfile && swapon /swapfile
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

echo "==> Getting code into $APP_DIR"
if [ -d "$APP_DIR/.git" ]; then
  git -C "$APP_DIR" pull --ff-only
else
  git clone "$REPO_URL" "$APP_DIR"
fi

cd "$APP_DIR/deploy"
if [ ! -f .env ]; then
  echo "==> Creating .env with generated secrets"
  cp .env.example .env
  sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=$(openssl rand -hex 24)|" .env
  sed -i "s|^JWT_SECRET_KEY=.*|JWT_SECRET_KEY=$(openssl rand -base64 64 | tr -d '\n/+=')|" .env
  chmod 600 .env
  echo
  echo "!! Edit $APP_DIR/deploy/.env now (optional email/SMTP settings), then run:"
  echo "   cd $APP_DIR/deploy && bash deploy.sh"
  exit 0
fi

bash deploy.sh
