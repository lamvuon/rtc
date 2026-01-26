#!/bin/bash

# 🔐 Setup Nginx với SSL Certificate (Let's Encrypt)
# Chạy script này trên EC2 server

set -e  # Exit on error

# Configuration file path
CONFIG_FILE="$(dirname "$0")/.env"

# Load configuration from .env if exists
if [ -f "$CONFIG_FILE" ]; then
    source "$CONFIG_FILE"
fi

# Configuration
# Nếu không truyền tham số và không có DOMAIN env, sẽ dùng APP_IP để tạo domain sslip.io (vd: 1.2.3.4 -> 1-2-3-4.sslip.io)
DOMAIN="${1:-${DOMAIN:-$( [ -n "${APP_IP}" ] && echo "${APP_IP//./-}.sslip.io" )}}"
EMAIL="${2:-${EMAIL:-admin@ec2.shop}}"  # Đổi thành email thật để Let's Encrypt chấp nhận
APP_PORT="${APP_PORT:-3000}"  # Port của Node.js app

echo "🚀 Setting up Nginx with SSL for: $DOMAIN"
echo "📧 Email: $EMAIL"
echo ""

# Kiểm tra xem đang chạy trên server không
if [ ! -d "/etc/nginx" ]; then
    echo "⚠️  Nginx chưa được cài đặt"
fi

# 1. Cài đặt Nginx nếu chưa có
if ! command -v nginx &> /dev/null; then
    echo "📦 Installing Nginx..."
    sudo apt-get update
    sudo apt-get install -y nginx
else
    echo "✅ Nginx đã được cài đặt"
fi

# 2. Cài đặt Certbot cho SSL
if ! command -v certbot &> /dev/null; then
    echo "📦 Installing Certbot..."
    sudo apt-get install -y certbot python3-certbot-nginx
else
    echo "✅ Certbot đã được cài đặt"
fi

# 3. Tạo cấu hình Nginx cơ bản (HTTP first)
echo "⚙️  Configuring Nginx..."
sudo tee /etc/nginx/sites-available/webrtc << EOF
# HTTP Server (sẽ redirect sang HTTPS sau khi có cert)
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    # Location cho Let's Encrypt verification
    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    # Proxy tới Node.js app
    location / {
        proxy_pass http://localhost:$APP_PORT;
        proxy_http_version 1.1;
        
        # WebSocket support
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        
        # Headers
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Timeouts for WebSocket
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
    }
}
EOF

# 4. Enable site
echo "🔗 Enabling site..."
sudo ln -sf /etc/nginx/sites-available/webrtc /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default

# 5. Test Nginx config
echo "🧪 Testing Nginx configuration..."
if sudo nginx -t; then
    echo "✅ Nginx config is valid"
else
    echo "❌ Nginx config has errors!"
    exit 1
fi

# 6. Reload Nginx
echo "🔄 Reloading Nginx..."
sudo systemctl reload nginx

# 7. Kiểm tra xem có phải domain thật không (không phải IP)
if [[ $DOMAIN =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo ""
    echo "⚠️  Bạn đang dùng IP address: $DOMAIN"
    echo "⚠️  Let's Encrypt chỉ cấp SSL cho domain name, không phải IP!"
    echo ""
    echo "📝 Để dùng SSL, bạn cần:"
    echo "   1. Mua domain (vd: example.com)"
    echo "   2. Point DNS A record của domain → IP EC2"
    echo "   3. Chạy lại: ./setup-nginx-ssl.sh your-domain.com your-email@example.com"
    echo ""
    echo "✅ Nginx đã được cấu hình (HTTP only)"
    echo "🌐 Truy cập: http://$DOMAIN"
    exit 0
fi

# 8. Lấy SSL Certificate từ Let's Encrypt
echo ""
echo "🔐 Obtaining SSL Certificate from Let's Encrypt..."
echo "⚠️  Đảm bảo domain $DOMAIN đã point DNS về IP này!"
read -p "Tiếp tục? (y/n) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Hủy bỏ SSL setup"
    echo "✅ Nginx đã được cấu hình (HTTP only)"
    exit 0
fi

# Get certificate
sudo certbot --nginx \
    -d "$DOMAIN" \
    --non-interactive \
    --agree-tos \
    --email "$EMAIL" \
    --redirect

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ SSL Certificate đã được cài đặt thành công!"
    echo "🔐 HTTPS đã được kích hoạt"
    echo ""
    echo "🌐 Truy cập:"
    echo "   - HTTPS: https://$DOMAIN"
    echo "   - HTTP:  http://$DOMAIN (auto redirect to HTTPS)"
    echo ""
    echo "📝 Certificate sẽ tự động renew trước khi hết hạn"
    echo "📋 Kiểm tra certbot timer:"
    echo "   sudo systemctl status certbot.timer"
else
    echo ""
    echo "❌ Không thể lấy SSL certificate!"
    echo "📝 Kiểm tra:"
    echo "   - Domain $DOMAIN đã point DNS về IP này chưa?"
    echo "   - Port 80 có bị firewall block không?"
    echo "   - Chạy manual: sudo certbot --nginx -d $DOMAIN"
    exit 1
fi

# 9. Setup auto-renewal (nếu chưa có)
if ! systemctl is-enabled certbot.timer &> /dev/null; then
    echo "⚙️  Enabling auto-renewal..."
    sudo systemctl enable certbot.timer
    sudo systemctl start certbot.timer
fi

echo ""
echo "🎉 Setup hoàn tất!"
echo ""
echo "📊 Nginx status:"
sudo systemctl status nginx --no-pager -l

echo ""
echo "🔐 SSL Certificate info:"
sudo certbot certificates
