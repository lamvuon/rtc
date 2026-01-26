#!/bin/bash

# 🎯 Stream Android screen via ADB → Server RTP
# Supports continuous restart (screenrecord 3-min limit)
# Audio: generates Opus silence (optional) to match server audio producer
# Usage:
#   ./example/stream-android-adb.sh
# Env:
#   ADB_SERIAL (optional): target device serial
#   SIZE (optional): screen size, default 1280x720
#   BITRATE (optional): video bitrate in bps, default 4000000
#   EC2_HOST, APP_IP(optional), KEY_FILE(optional), REMOTE_DIR(optional) in .env

set -e

# Load environment
ENV_FILE="$(dirname "$0")/../.env"
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

# Check adb
if ! command -v adb >/dev/null 2>&1; then
  echo "❌ adb không có trong PATH. Cài Android platform-tools."
  exit 1
fi

# Pick device
SERIAL="$ADB_SERIAL"
if [ -z "$SERIAL" ]; then
  SERIAL=$(adb devices | awk '/\tdevice$/{print $1}' | head -n1)
fi
if [ -z "$SERIAL" ]; then
  echo "❌ Không tìm thấy thiết bị Android. Kết nối USB/ADB và chạy 'adb devices'"
  exit 1
fi

SIZE="${SIZE:-1280x720}"
BITRATE="${BITRATE:-4000000}"

echo "Using EC2_HOST=$EC2_HOST"
echo "Using EC2_IP=$EC2_IP"
echo "Using REMOTE_DIR=$REMOTE_DIR"
echo "Using ANDROID_SERIAL=$SERIAL"

# Restart server to emit fresh RTP ports
echo "🔄 Restarting server to get fresh RTP ports..."
ssh -i "$KEY_FILE" "$EC2_HOST" 'pm2 restart web-rtc' > /dev/null 2>&1 || true
sleep 3

# Fetch RTP ports
echo "🔍 Đang lấy RTP ports từ EC2..."
VIDEO_PORT=$(ssh -i "$KEY_FILE" "$EC2_HOST" 'pm2 logs web-rtc --nostream --lines 50 | grep "Video RTP port:" | tail -1 | grep -o "[0-9]*$"')
AUDIO_PORT=$(ssh -i "$KEY_FILE" "$EC2_HOST" 'pm2 logs web-rtc --nostream --lines 50 | grep "Audio RTP port:" | tail -1 | grep -o "[0-9]*$"')

if [ -z "$VIDEO_PORT" ] || [ -z "$AUDIO_PORT" ]; then
  echo "❌ Không tìm thấy RTP ports!"
  ssh -i "$KEY_FILE" "$EC2_HOST" 'pm2 logs web-rtc --nostream --lines 50'
  exit 1
fi

echo "✅ Video RTP Port: $VIDEO_PORT"
echo "✅ Audio RTP Port: $AUDIO_PORT"

echo "🌐 Mở browser: http://$EC2_IP"

# Kill any existing local FFmpeg
pkill -9 ffmpeg 2>/dev/null || true
sleep 1

# Start AUDIO (silence) → Opus → RTP
ffmpeg -f lavfi -i anullsrc=r=48000:cl=stereo \
  -c:a libopus -b:a 128k -ar 48000 -ac 2 \
  -payload_type 97 -ssrc 22222222 \
  -f rtp "rtp://$EC2_IP:$AUDIO_PORT?pkt_size=1200" &
AUDIO_PID=$!

# Function to run a single screenrecord→ffmpeg pass
run_once() {
  echo "▶️  Starting ADB screenrecord (size=$SIZE bitrate=$BITRATE)"
  # Note: screenrecord has ~3 min limit; we auto-restart in loop
  adb -s "$SERIAL" exec-out screenrecord \
    --size "$SIZE" \
    --bit-rate "$BITRATE" \
    --output-format=h264 - | \
  ffmpeg -re -fflags +nobuffer -i - \
    -an \
    -c:v libx264 -profile:v baseline -level 3.1 \
    -preset veryfast -tune zerolatency \
    -g 30 -keyint_min 30 -sc_threshold 0 \
    -b:v 1500k -maxrate 1500k -bufsize 3000k \
    -pix_fmt yuv420p \
    -payload_type 96 -ssrc 11111111 \
    -f rtp "rtp://$EC2_IP:$VIDEO_PORT?pkt_size=1200"
}

# Loop to keep streaming
(while true; do
  run_once || true
  echo "🔁 Restarting screenrecord in 2s..."
  sleep 2
done) &
VIDEO_LOOP_PID=$!

trap "echo ''; echo '⏹️  Stopping streams...'; kill $VIDEO_LOOP_PID $AUDIO_PID 2>/dev/null; exit 0" INT

echo "✅ Streaming started!"
echo "   Android Video → rtp://$EC2_IP:$VIDEO_PORT (via adb screenrecord)"
echo "   Audio (silence) → rtp://$EC2_IP:$AUDIO_PORT"

wait $VIDEO_LOOP_PID
wait $AUDIO_PID
