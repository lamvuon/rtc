#!/bin/bash

# Push local workspace to EC2 (same as deploy sync, no remote commands)

# Configuration
: "${EC2_HOST:?EC2_HOST is not set. Please set it in ~/.bashrc}"
KEY_FILE="${KEY_FILE:-${HOME}/.ssh/lamvuonshop.pem}"
REMOTE_DIR="${REMOTE_DIR:-/home/ubuntu}"

echo "📦 Pushing files to EC2 (rsync only)..."
echo "Using EC2_HOST=$EC2_HOST"
echo "Using REMOTE_DIR=$REMOTE_DIR"
ssh -i $KEY_FILE $EC2_HOST "mkdir -p $REMOTE_DIR"
rsync -avz -e "ssh -i $KEY_FILE" \
  --filter=':- .gitignore' \
  --exclude '.git' \
  ./ $EC2_HOST:$REMOTE_DIR/

echo "✅ Push finished (no remote commands run)."
