#!/bin/bash

# 🎯 Stream RTSP camera/source → Server via RTP
# Usage:
#   ./stream-rtsp.sh rtsp://user:pass@CAMERA_HOST:PORT/path
# Requires: .env with EC2_HOST, optional KEY_FILE, REMOTE_DIR

RTSP_URL="$1"
if [ -z "$RTSP_URL" ]; then
  echo "❌ Missing RTSP URL argument"
  echo "🔧 Usage: ./stream-rtsp.sh rtsp://user:pass@CAMERA_HOST:PORT/path"
  exit 1
fi

# Load environment from .env file next to script
ENV_FILE="$(dirname "$0")/.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "❌ File .env không tìm thấy tại $ENV_FILE"
  echo "ℹ️  Tạo .env với các biến: EC2_HOST, APP_IP(optional), KEY_FILE(optional), REMOTE_DIR(optional)"
  exit 1
fi
source "$ENV_FILE"

: "${EC2_HOST:?EC2_HOST is not set. Please set it in .env}"
APP_IP="${APP_IP:-${EC2_HOST#*@}}"
EC2_IP="$APP_IP"
KEY_FILE="${KEY_FILE:-${HOME}/.ssh/ec2.pem}"
REMOTE_DIR="${REMOTE_DIR:-/home/ubuntu/web-rtc}"

echo "Using EC2_HOST=$EC2_HOST"
echo "Using EC2_IP=$EC2_IP"
echo "Using REMOTE_DIR=$REMOTE_DIR"
echo "Using RTSP_URL=$RTSP_URL"

# Restart server to emit fresh RTP ports
echo "🔄 Restarting server to get fresh RTP ports..."
ssh -i "$KEY_FILE" "$EC2_HOST" 'pm2 restart web-rtc' > /dev/null 2>&1
sleep 3

# Fetch RTP ports from server logs
echo "🔍 Đang lấy RTP ports từ EC2..."
VIDEO_PORT=$(ssh -i "$KEY_FILE" "$EC2_HOST" 'pm2 logs web-rtc --nostream --lines 50 | grep "Video RTP port:" | tail -1 | grep -o "[0-9]*$"')
AUDIO_PORT=$(ssh -i "$KEY_FILE" "$EC2_HOST" 'pm2 logs web-rtc --nostream --lines 50 | grep "Audio RTP port:" | tail -1 | grep -o "[0-9]*$"')

if [ -z "$VIDEO_PORT" ] || [ -z "$AUDIO_PORT" ]; then
  echo "❌ Không tìm thấy RTP ports!"
  echo "📋 Logs từ EC2:"
  ssh -i "$KEY_FILE" "$EC2_HOST" 'pm2 logs web-rtc --nostream --lines 50'
  exit 1
fi

echo "✅ Video RTP Port: $VIDEO_PORT"
echo "✅ Audio RTP Port: $AUDIO_PORT"
echo "🌐 Mở browser: http://$EC2_IP"

# Kill any existing local FFmpeg
pkill -9 ffmpeg 2>/dev/null || true
sleep 1

echo "🚀 Đang stream RTSP → RTP..."
echo "   Nhấn Ctrl+C để dừng"

# VIDEO: re-encode to H264 baseline to match server codec, fixed PT/SSRC
ffmpeg -rtsp_transport tcp -i "$RTSP_URL" \
  -an \
  -c:v libx264 \
  -profile:v baseline \
  -level 3.1 \
  -preset veryfast \
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
  "rtp://$EC2_IP:$VIDEO_PORT?pkt_size=1200" &

VIDEO_PID=$!

# AUDIO: encode to Opus, fixed PT/SSRC
ffmpeg -rtsp_transport tcp -i "$RTSP_URL" \
  -vn \
  -c:a libopus \
  -b:a 128k \
  -ar 48000 \
  -ac 2 \
  -payload_type 97 \
  -ssrc 22222222 \
  -f rtp \
  "rtp://$EC2_IP:$AUDIO_PORT?pkt_size=1200" &

AUDIO_PID=$!

trap "echo ''; echo '⏹️  Stopping streams...'; kill $VIDEO_PID $AUDIO_PID 2>/dev/null; exit 0" INT

echo "✅ Streaming started!"
echo "   RTSP Video → rtp://$EC2_IP:$VIDEO_PORT"
echo "   RTSP Audio → rtp://$EC2_IP:$AUDIO_PORT"

wait $VIDEO_PID
wait $AUDIO_PID
