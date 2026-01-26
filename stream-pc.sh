#!/bin/bash

# 🎯 CÁCH CHUẨN: Stream từ PC → EC2 bằng RTP
# Yêu cầu: video.mp4 phải có sẵn trên PC

# Load environment from .env file
ENV_FILE="$(dirname "$0")/.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "❌ File .env không tìm thấy tại $ENV_FILE"
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

# BƯỚC 1: Restart server để lấy RTP ports
echo "🔄 Restarting server to get fresh RTP ports..."
ssh -i $KEY_FILE $EC2_HOST 'pm2 restart web-rtc' > /dev/null 2>&1
sleep 3

# BƯỚC 2: Lấy RTP ports từ EC2
echo "🔍 Đang lấy RTP ports từ EC2..."
VIDEO_PORT=$(ssh -i $KEY_FILE $EC2_HOST 'pm2 logs web-rtc --nostream --lines 50 | grep "Video RTP port:" | tail -1 | grep -o "[0-9]*$"')
AUDIO_PORT=$(ssh -i $KEY_FILE $EC2_HOST 'pm2 logs web-rtc --nostream --lines 50 | grep "Audio RTP port:" | tail -1 | grep -o "[0-9]*$"')

if [ -z "$VIDEO_PORT" ] || [ -z "$AUDIO_PORT" ]; then
  echo "❌ Không tìm thấy RTP ports!"
  echo "📋 Logs từ EC2:"
  ssh -i $KEY_FILE $EC2_HOST 'pm2 logs web-rtc --nostream --lines 20'
  exit 1
fi

echo "✅ Video RTP Port: $VIDEO_PORT"
echo "✅ Audio RTP Port: $AUDIO_PORT"
echo ""
echo "🎬 Stream từ PC → EC2 ($EC2_IP)"
echo "📹 Đảm bảo file video.mp4 có sẵn trong thư mục hiện tại"
echo "🌐 Mở browser: http://$EC2_IP"
echo ""

# BƯỚC 3: Stream từ PC → EC2 bằng RTP
# Kiểm tra file video
if [ ! -f "video.mp4" ]; then
  echo "❌ Không tìm thấy file video.mp4 trong thư mục hiện tại!"
  echo "💡 Tạo symlink hoặc copy video của bạn thành video.mp4"
  exit 1
fi

echo "🚀 Đang stream..."
echo "   Nhấn Ctrl+C để dừng"
echo ""

# Kill any existing local FFmpeg
pkill -9 ffmpeg 2>/dev/null || true
sleep 1

# Stream VIDEO từ PC → EC2 (loop vô hạn)
ffmpeg -re -stream_loop -1 -i video.mp4 \
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
  rtp://$EC2_IP:$VIDEO_PORT?pkt_size=1200 &

VIDEO_PID=$!

# Stream AUDIO từ PC → EC2 (loop vô hạn)
ffmpeg -re -stream_loop -1 -i video.mp4 \
  -vn \
  -c:a libopus \
  -b:a 128k \
  -ar 48000 \
  -ac 2 \
  -payload_type 97 \
  -ssrc 22222222 \
  -f rtp \
  rtp://$EC2_IP:$AUDIO_PORT?pkt_size=1200 &

AUDIO_PID=$!

# Chờ cho đến khi user nhấn Ctrl+C
trap "echo ''; echo '⏹️  Stopping streams...'; kill $VIDEO_PID $AUDIO_PID 2>/dev/null; exit 0" INT

echo "✅ Streaming started!"
echo "   Video: PC → rtp://$EC2_IP:$VIDEO_PORT"
echo "   Audio: PC → rtp://$EC2_IP:$AUDIO_PORT"
echo ""

wait $VIDEO_PID
wait $AUDIO_PID
