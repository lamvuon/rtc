#!/bin/bash

# Configuration
: "${EC2_HOST:?EC2_HOST is not set. Please set it in ~/.bashrc}"  # EC2 host must come from the environment
KEY_FILE="${KEY_FILE:-${HOME}/.ssh/lamvuonshop.pem}"
REMOTE_DIR="${REMOTE_DIR:-$(pwd)}"  # Deploy to a directory matching the current path

APP_IP="${APP_IP:-${EC2_HOST#*@}}"

echo "🚀 Starting deployment to EC2..."
echo "Using EC2_HOST=$EC2_HOST"
echo "Using REMOTE_DIR=$REMOTE_DIR"
echo "Using APP_IP=$APP_IP"

# 1. Copy files to EC2
echo "📦 Copying files to EC2..."
rsync -avz -e "ssh -i $KEY_FILE" \
  --filter=':- .gitignore' \
  --exclude '.git' \
  ./ $EC2_HOST:$REMOTE_DIR/

# 2. SSH into EC2 and setup
echo "⚙️ Setting up on EC2..."
ssh -i $KEY_FILE $EC2_HOST << ENDSSH

cd "$REMOTE_DIR"

# Install Node.js if not exists
if ! command -v node &> /dev/null; then
  echo "📥 Installing Node.js..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get install -y nodejs
fi

# Install dependencies
echo "📦 Installing npm packages..."
npm install

# Install nginx if not exists (config is handled by setup-nginx-ssl.sh)
if ! command -v nginx &> /dev/null; then
  echo "📥 Installing nginx..."
  sudo apt-get update
  sudo apt-get install -y nginx
else
  echo "✅ Nginx already installed (config managed by setup-nginx-ssl.sh)"
fi

# Install PM2 for process management
if ! command -v pm2 &> /dev/null; then
  echo "📥 Installing PM2..."
  sudo npm install -g pm2
fi

# Start/Restart the application
echo "🚀 Starting application with PM2..."
pm2 delete web-rtc 2>/dev/null || true
pm2 start server.js --name web-rtc
pm2 save
pm2 startup | tail -n 1 | sudo bash

echo "✅ Deployment completed!"
echo ""
echo "📊 Application status:"
pm2 status

echo ""
echo "🔥 RTP port will be displayed in logs:"
pm2 logs web-rtc --lines 20 --nostream

ENDSSH

echo ""
echo "✅ Deployment finished!"
echo ""
echo "🌐 Access your application at: http://$APP_IP"
echo "📊 View logs: ssh -i $KEY_FILE $EC2_HOST 'pm2 logs web-rtc'"
echo "⚙️ Manage app: ssh -i $KEY_FILE $EC2_HOST 'pm2 [start|stop|restart] web-rtc'"
