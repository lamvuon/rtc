#!/bin/bash
# Run nginx+SSL setup on EC2 from this PC
# Usage: ./run-setup-nginx-ssl-remote.sh [domain_or_ip] [email]

set -e

# Configuration file path
CONFIG_FILE="$(dirname "$0")/.env"

# Load configuration from .env if exists
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
fi

: "${EC2_HOST:?EC2_HOST is not set. Please set it in .env}"
KEY_FILE="${KEY_FILE:-${HOME}/.ssh/lamvuonshop.pem}"
REMOTE_DIR="${REMOTE_DIR:-/home/ubuntu}"
APP_IP="${APP_IP:-${EC2_HOST#*@}}"
DOMAIN="${1:-${DOMAIN:-$( [ -n "${APP_IP}" ] && echo "${APP_IP//./-}.sslip.io" )}}"
EMAIL="${2:-${EMAIL:-admin@lamvuon.shop}}"
  
echo "📦 Syncing scripts to EC2..."
echo "Using EC2_HOST=$EC2_HOST"
echo "Using REMOTE_DIR=$REMOTE_DIR"
echo "Using DOMAIN=$DOMAIN"
ssh -i $KEY_FILE $EC2_HOST "mkdir -p $REMOTE_DIR"
rsync -avz -e "ssh -i $KEY_FILE" \
  --filter=':- .gitignore' \
  --exclude '.git' \
  ./setup-nginx-ssl.sh $EC2_HOST:$REMOTE_DIR/

echo "🔗 Running setup-nginx-ssl.sh on EC2..."
ssh -i $KEY_FILE $EC2_HOST "cd $REMOTE_DIR && chmod +x setup-nginx-ssl.sh && ./setup-nginx-ssl.sh $DOMAIN $EMAIL"

echo "✅ Done."
