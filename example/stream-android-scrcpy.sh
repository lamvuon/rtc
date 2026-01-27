#!/bin/bash

# 🎯 Stable streaming via scrcpy (v4l2loopback) → FFmpeg → RTP
# This approach avoids screenrecord time limits by piping frames to a v4l2 device.
# Requirements:
#   - scrcpy >= 2.0
#   - v4l2loopback kernel module (to create /dev/videoX)
#   - ffmpeg
# Usage:
#   ./example/stream-android-scrcpy.sh
# Env options:
#   ADB_SERIAL (optional): specific Android device serial
#   V4L2_DEV (optional): v4l2 device path, default /dev/video10
#   BITRATE (optional): scrcpy bitrate (e.g. 8000000 for 8M)
#   FPS (optional): scrcpy max fps, default 60
#   SIZE (optional): scrcpy max size (longer side), default 1280
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

# Defaults - Ultra low latency mode
SERIAL="${ADB_SERIAL}"  # may be empty
V4L2_DEV="${V4L2_DEV:-/dev/video10}"
BITRATE="${BITRATE:-2000000}"  # 2Mbps (reduced from 3Mbps)
FPS="${FPS:-20}"              # 20fps (reduced from 25fps)
SIZE="${SIZE:-480}"           # 480p (reduced from 720p)

# Check tools
for cmd in adb scrcpy ffmpeg; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "❌ $cmd không có trong PATH"
    exit 1
  fi
done

# Ensure v4l2loopback is loaded and device exists
if ! lsmod | grep -q "v4l2loopback"; then
  echo "🔧 Loading v4l2loopback kernel module... (requires sudo)"
  if ! sudo -n modprobe v4l2loopback devices=1 video_nr=10 card_label="AndroidScrcpy" exclusive_caps=1 2>/dev/null; then
    echo "❌ Không thể load v4l2loopback tự động. Chạy lệnh sau và thử lại:"
    echo "    sudo modprobe v4l2loopback devices=1 video_nr=10 card_label=AndroidScrcpy exclusive_caps=1"
    exit 1
  fi
fi

# Create device if missing
if [ ! -e "$V4L2_DEV" ]; then
  echo "❌ $V4L2_DEV chưa tồn tại. Vui lòng đảm bảo v4l2loopback tạo đúng video_nr."
  echo "   Mẹo: đặt V4L2_DEV=/dev/videoN hoặc modprobe với video_nr=N"
  exit 1
fi

# Pick device if SERIAL not set
if [ -z "$SERIAL" ]; then
  SERIAL=$(adb devices | awk '/\tdevice$/{print $1}' | head -n1)
fi
if [ -z "$SERIAL" ]; then
  echo "❌ Không tìm thấy thiết bị Android. Kết nối USB/ADB và chạy 'adb devices'"
  exit 1
fi

echo "Using EC2_HOST=$EC2_HOST"
echo "Using EC2_IP=$EC2_IP"
echo "Using REMOTE_DIR=$REMOTE_DIR"
echo "Using ANDROID_SERIAL=$SERIAL"
echo "Using V4L2_DEV=$V4L2_DEV (bitrate=$BITRATE fps=$FPS size=$SIZE)"

# Restart server to emit fresh RTP ports
echo "🔄 Restarting server to get fresh RTP ports..."
ssh -i "$KEY_FILE" "$EC2_HOST" 'pm2 restart web-rtc' > /dev/null 2>&1 || true
sleep 3

# Fetch RTP ports from server logs
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

# Kill any existing local processes
pkill -9 ffmpeg 2>/dev/null || true
pkill -9 scrcpy 2>/dev/null || true
sleep 1

# Start scrcpy pumping frames to v4l2 device (with display window)
echo "🚀 Starting scrcpy → $V4L2_DEV"
SCRCPY_CMD=(scrcpy --serial "$SERIAL" --v4l2-sink "$V4L2_DEV" --bit-rate "$BITRATE" --max-fps "$FPS" --max-size "$SIZE")
"${SCRCPY_CMD[@]}" &
SCRCPY_PID=$!

# Wait for scrcpy to initialize v4l2 device (increased delay)
echo "⏳ Waiting for v4l2 device initialization..."
sleep 3

# Verify v4l2 device is ready
if ! v4l2-ctl --device="$V4L2_DEV" --all >/dev/null 2>&1; then
  echo "⚠️ v4l2 device not ready yet, waiting 2 more seconds..."
  sleep 2
fi

# Start AUDIO (silence) → Opus → RTP (minimal bitrate)
ffmpeg -f lavfi -i anullsrc=r=48000:cl=stereo \
  -c:a libopus -b:a 32k -ar 48000 -ac 2 \
  -payload_type 97 -ssrc 22222222 \
  -f rtp "rtp://$EC2_IP:$AUDIO_PORT?pkt_size=1200" &
AUDIO_PID=$!

# Start VIDEO encoding from v4l2 → H264 baseline → RTP (ultra low latency)
ffmpeg -f v4l2 -i "$V4L2_DEV" \
  -an \
  -c:v libx264 -profile:v baseline -level 3.0 \
  -preset ultrafast -tune zerolatency \
  -g 60 -keyint_min 20 -sc_threshold 0 \
  -b:v 600k -maxrate 800k -bufsize 1000k \
  -pix_fmt yuv420p \
  -threads 2 \
  -payload_type 96 -ssrc 11111111 \
  -f rtp "rtp://$EC2_IP:$VIDEO_PORT?pkt_size=1200" &
VIDEO_PID=$!

trap "echo ''; echo '⏹️  Stopping streams...'; kill $VIDEO_PID $AUDIO_PID $SCRCPY_PID 2>/dev/null; exit 0" INT

echo "✅ Streaming started!"
echo "   Android Video (scrcpy→$V4L2_DEV) → rtp://$EC2_IP:$VIDEO_PORT"
echo "   Audio (silence) → rtp://$EC2_IP:$AUDIO_PORT"

wait $VIDEO_PID
wait $AUDIO_PID
wait $SCRCPY_PID
