#!/bin/bash

# 🎯 Stream từ nguồn tùy chỉnh → EC2
# Usage: ./stream-custom.sh <input-source>
# Example: ./stream-custom.sh /path/to/video.mp4
#          ./stream-custom.sh rtsp://camera-ip:554/stream
#          ./stream-custom.sh /dev/video0

: "${EC2_HOST:?EC2_HOST is not set. Please set it in ~/.bashrc}"
APP_IP="${APP_IP:-${EC2_HOST#*@}}"
EC2_IP="$APP_IP"
KEY_FILE="${KEY_FILE:-${HOME}/.ssh/lamvuonshop.pem}"

# Lấy input source từ tham số hoặc mặc định video.mp4
INPUT_SOURCE="${1:-video.mp4}"

echo "Using EC2_HOST=$EC2_HOST"
echo "Using EC2_IP=$EC2_IP"
echo "Using INPUT_SOURCE=$INPUT_SOURCE"

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
echo "🎬 Stream từ $INPUT_SOURCE → EC2 ($EC2_IP)"
echo "🌐 Mở browser: http://$EC2_IP"
echo ""

echo "🚀 Đang stream..."
echo "   Nhấn Ctrl+C để dừng"
echo ""

# Kill any existing local FFmpeg
pkill -9 ffmpeg 2>/dev/null || true
sleep 1

# Detect input type
INPUT_ARGS="-re -i $INPUT_SOURCE"

# Special handling for devices
if [[ "$INPUT_SOURCE" == /dev/video* ]]; then
  INPUT_ARGS="-re -f v4l2 -i $INPUT_SOURCE"
elif [[ "$INPUT_SOURCE" == rtsp://* ]]; then
  INPUT_ARGS="-re -rtsp_transport tcp -i $INPUT_SOURCE"
elif [[ "$INPUT_SOURCE" == http://* ]] || [[ "$INPUT_SOURCE" == https://* ]]; then
  INPUT_ARGS="-re -i $INPUT_SOURCE"
elif [[ "$INPUT_SOURCE" == *.m3u8 ]]; then
  INPUT_ARGS="-re -i $INPUT_SOURCE"
fi

# Stream VIDEO từ nguồn → EC2
ffmpeg $INPUT_ARGS \
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

# Stream AUDIO từ nguồn → EC2
ffmpeg $INPUT_ARGS \
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
echo "   Video: $INPUT_SOURCE → rtp://$EC2_IP:$VIDEO_PORT"
echo "   Audio: $INPUT_SOURCE → rtp://$EC2_IP:$AUDIO_PORT"
echo ""

wait $VIDEO_PID
wait $AUDIO_PID
