#!/bin/bash

# Configuration file path
CONFIG_FILE="$(dirname "$0")/.env"

# Load configuration from .env if exists
if [ -f "$CONFIG_FILE" ]; then
  source "$CONFIG_FILE"
fi

: "${EC2_HOST:?EC2_HOST is not set. Please set it in .env}"
APP_IP="${APP_IP:-${EC2_HOST#*@}}"
KEY_FILE="${KEY_FILE:-${HOME}/.ssh/lamvuonshop.pem}"

echo "Using EC2_HOST=$EC2_HOST"
echo "Using APP_IP=$APP_IP"
echo "Using KEY_FILE=$KEY_FILE"

# Restart server to get fresh RTP ports
echo "🔄 Restarting server to get RTP ports..."
ssh -i "$KEY_FILE" "$EC2_HOST" 'pm2 restart web-rtc' > /dev/null 2>&1
sleep 3

# Get the latest Video and Audio RTP ports from PM2 logs
echo "🔍 Đang lấy RTP ports từ server..."
VIDEO_PORT=$(ssh -i "$KEY_FILE" "$EC2_HOST" 'pm2 logs web-rtc --nostream --lines 50 | grep "Video RTP port:" | tail -1 | grep -o "[0-9]*$"')
AUDIO_PORT=$(ssh -i "$KEY_FILE" "$EC2_HOST" 'pm2 logs web-rtc --nostream --lines 50 | grep "Audio RTP port:" | tail -1 | grep -o "[0-9]*$"')

if [ -z "$VIDEO_PORT" ] || [ -z "$AUDIO_PORT" ]; then
  echo "❌ Không tìm thấy RTP ports!"
  echo "📋 Logs:"
  ssh -i "$KEY_FILE" "$EC2_HOST" 'pm2 logs web-rtc --nostream --lines 20 | grep -E "(Video|Audio|RTP)"'
  exit 1
fi

echo "✅ Video RTP Port: $VIDEO_PORT"
echo "✅ Audio RTP Port: $AUDIO_PORT"
echo ""
echo "🎬 Đang stream FFmpeg với audio đến EC2..."

# Run FFmpeg on EC2
ssh -i "$KEY_FILE" "$EC2_HOST" << EOF
cd ~
echo "📹 Starting FFmpeg stream to ports Video:$VIDEO_PORT Audio:$AUDIO_PORT"
echo "🌐 Open http://$APP_IP in your browser"
echo ""

# Kill any existing FFmpeg process
pkill -9 ffmpeg 2>/dev/null || true
sleep 1

# Stream with audio (loop forever)
while true; do
  ffmpeg -re -i test-video.mp4 \
    -an \
    -c:v libx264 \
    -profile:v baseline \
    -level 3.1 \
    -preset ultrafast \
    -tune zerolatency \
    -g 30 \
    -keyint_min 30 \
    -sc_threshold 0 \
    -b:v 1500k \
    -maxrate 1500k \
    -bufsize 3000k \
    -pix_fmt yuv420p \
    -payload_type 96 \
    -ssrc 11111111 \
    -f rtp \
    rtp://127.0.0.1:$VIDEO_PORT?pkt_size=1200 &
  
  VIDEO_PID=\$!
  
  ffmpeg -re -i test-video.mp4 \
    -vn \
    -c:a libopus \
    -b:a 128k \
    -ar 48000 \
    -ac 2 \
    -payload_type 97 \
    -ssrc 22222222 \
    -f rtp \
    rtp://127.0.0.1:$AUDIO_PORT?pkt_size=1200 &
  
  AUDIO_PID=\$!
  
  # Wait for both processes
  wait \$VIDEO_PID
  wait \$AUDIO_PID
  
  echo "🔄 Video ended, restarting..."
  sleep 1
done
EOF
