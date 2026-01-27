#!/bin/bash

# 🎯 Stream từ scrcpy đang chạy sẵn (không kill scrcpy hiện tại)
# Dùng script này khi bạn đã chạy scrcpy với v4l2-sink ở luồng khác
# Requirements:
#   - scrcpy đã chạy với --v4l2-sink /dev/video10
#   - ffmpeg
# Usage:
#   ./example/stream-existing-scrcpy.sh
# Env options:
#   V4L2_DEV (optional): v4l2 device path, default /dev/video10
#   EC2_HOST, APP_IP(optional), KEY_FILE(optional), REMOTE_DIR(optional) in .env

set -e

# Load environment
ENV_FILE="$(dirname "$0")/../.env"
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

# Defaults
V4L2_DEV="${V4L2_DEV:-/dev/video10}"

# Check v4l2 device exists
if [ ! -e "$V4L2_DEV" ]; then
  echo "❌ $V4L2_DEV không tồn tại. Đảm bảo scrcpy đang chạy với --v4l2-sink"
  exit 1
fi

# Check if v4l2 device has video stream
if ! v4l2-ctl --device="$V4L2_DEV" --all 2>/dev/null | grep -q "Format Video Capture"; then
  echo "❌ $V4L2_DEV không có video stream. Kiểm tra scrcpy đang chạy đúng không."
  exit 1
fi

echo "Using EC2_HOST=$EC2_HOST"
echo "Using EC2_IP=$EC2_IP"
echo "Using V4L2_DEV=$V4L2_DEV"

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

# Start AUDIO (silence) → Opus → RTP (minimal bitrate)
echo "🎵 Starting audio stream..."
ffmpeg -f lavfi -i anullsrc=r=48000:cl=stereo \
  -c:a libopus -b:a 32k -ar 48000 -ac 2 \
  -payload_type 97 -ssrc 22222222 \
  -f rtp "rtp://$EC2_IP:$AUDIO_PORT?pkt_size=1200" &
AUDIO_PID=$!

# Start VIDEO encoding from v4l2 → H264 baseline → RTP (ultra low latency)
echo "📹 Starting video stream from $V4L2_DEV..."
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

trap "echo ''; echo '⏹️  Stopping streams (keeping scrcpy)...'; kill $VIDEO_PID $AUDIO_PID 2>/dev/null; exit 0" INT

echo ""
echo "✅ Streaming started!"
echo "   📺 Video từ $V4L2_DEV → rtp://$EC2_IP:$VIDEO_PORT"
echo "   🎵 Audio (silence) → rtp://$EC2_IP:$AUDIO_PORT"
echo "   ⚠️  Scrcpy vẫn chạy độc lập ở luồng khác"
echo ""
echo "Press Ctrl+C to stop streaming (scrcpy sẽ vẫn chạy)"

wait $VIDEO_PID
wait $AUDIO_PID
