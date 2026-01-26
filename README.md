# WebRTC MediaSoup Server

MediaSoup WebRTC server cho phép nhận video/audio từ FFmpeg (hoặc PC streaming) qua RTP và phát lại cho trình duyệt thông qua WebRTC.

## 📋 Tóm tắt

- **Server:** Node.js + Express + MediaSoup 3.13.24
- **Signaling:** WebSocket
- **Codec:** H264 (video), Opus (audio)
- **RTP Input:** FFmpeg gửi RTP đến server
- **WebRTC Output:** Browser nhận stream từ server

---

## 🚀 Cách chạy

### Option 1: Chạy trực tiếp (Local)

#### Yêu cầu
- Node.js >= 18.0.0
- FFmpeg (nếu stream từ video file)

#### Bước 1: Cài đặt dependencies
```bash
npm install
```

#### Bước 2: Tạo file `.env`
```env
APP_IP=localhost
APP_PORT=3000
```

**Lưu ý:** Trên server EC2, đặt `APP_IP` = **public IP của instance**

#### Bước 3: Chạy server
```bash
npm start
```

Server sẽ khởi động tại `http://localhost:3000`

---

### Option 2: Chạy với Docker (Recommended)

#### Bước 1: Build image
```bash
docker build -t web-rtc-mediasoup .
```

#### Bước 2: Chạy container
```bash
docker run -d \
  --name web-rtc-server \
  -p 3000:3000 \
  -p 10000-10100:10000-10100/udp \
  -p 10000-10100:10000-10100/tcp \
  -e APP_IP=<YOUR_SERVER_IP> \
  web-rtc-mediasoup
```

Thay `<YOUR_SERVER_IP>` bằng IP công cộng của server.

#### Bước 3: Chạy với Docker Compose
```bash
export APP_IP=<YOUR_SERVER_IP>
docker-compose up -d
```

---

## 📡 Port Requirements

### Cần mở những port nào trên Firewall/Security Group?

#### **1. HTTP Port**
| Protocol | Port | Loại | Mục đích |
|----------|------|------|---------|
| TCP | 3000 | Inbound | WebSocket signaling (Browser ↔ Server) |

#### **2. WebRTC/RTP Ports**
| Protocol | Port Range | Loại | Mục đích |
|----------|-----------|------|---------|
| UDP | 10000-10100 | Inbound/Outbound | WebRTC media (Browser ↔ Server) |
| TCP | 10000-10100 | Inbound/Outbound | WebRTC fallback (nếu UDP bị block) |

#### **3. RTP Ports (từ FFmpeg)**
| Protocol | Port Range | Loại | Mục đích |
|----------|-----------|------|---------|
| UDP | 20000-40000 | Inbound | Nhận RTP từ FFmpeg/PC |

---

## 📌 Cấu hình AWS Security Group (EC2)

Vào AWS Console → Security Groups → Thêm Inbound Rules:

```
Rule 1: Type HTTP, Protocol TCP, Port 3000, Source 0.0.0.0/0
Rule 2: Type Custom UDP, Protocol UDP, Port Range 10000-10100, Source 0.0.0.0/0
Rule 3: Type Custom UDP, Protocol UDP, Port Range 20000-40000, Source 0.0.0.0/0
Rule 4: Type Custom TCP, Protocol TCP, Port Range 10000-10100, Source 0.0.0.0/0
```

---

## 🎬 Streaming từ FFmpeg

### Từ Video File
```bash
ffmpeg -re -i video.mp4 \
  -f rtp \
  -c:v h264 \
  -rtpflags latm \
  'rtp://SERVER_IP:20000' \
  -c:a libopus \
  'rtp://SERVER_IP:20001'
```

### Từ Webcam (Linux)
```bash
ffmpeg -f v4l2 -i /dev/video0 \
  -f rtp \
  -c:v h264 \
  'rtp://SERVER_IP:20000' \
  -c:a libopus \
  'rtp://SERVER_IP:20001'
```

### Từ Screen Capture (Linux)
```bash
ffmpeg -f x11grab -i :0.0 \
  -f rtp \
  -c:v h264 \
  'rtp://SERVER_IP:20000' \
  -c:a libopus \
  'rtp://SERVER_IP:20001'

### Từ RTSP Camera/Source
```bash
# Re-encode to H264 baseline + Opus to match server
ffmpeg -rtsp_transport tcp -i rtsp://user:pass@CAMERA_HOST:PORT/path \
  -f rtp \
  -c:v libx264 -profile:v baseline -level 3.1 -tune zerolatency \
  'rtp://SERVER_IP:20000' \
  -c:a libopus -ar 48000 -ac 2 \
  'rtp://SERVER_IP:20001'
```

Hoặc dùng script tiện lợi:

```bash
# .env cần có EC2_HOST (vd: ubuntu@1.2.3.4), optional KEY_FILE
./stream-rtsp.sh rtsp://user:pass@CAMERA_HOST:PORT/path
```
```

---

## 🌐 Kết nối từ Browser

1. Mở `http://SERVER_IP:3000` trên trình duyệt
2. Server sẽ gửi:
   - Router RTP capabilities
   - Video/Audio producer IDs
3. Browser tạo WebRTC transport
4. Browser nhận video/audio stream

### Client nên support:
- H264 video codec
- Opus audio codec
- WebRTC

---

## 🔍 Kiểm tra Server đang chạy

```bash
# Check nếu chạy trực tiếp
curl http://localhost:3000

# Check logs nếu chạy Docker
docker logs -f web-rtc-server

# Check port listening
netstat -tlnp | grep 3000
netstat -ulnp | grep 20000
```

---

## ⚙️ Cấu hình Advanced

### Thay đổi port HTTP
Sửa trong `server.js`:
```javascript
const APP_PORT = Number(process.env.APP_PORT || 3000);
```

### Thay đổi RTP port range
Sửa trong `server.js`:
```javascript
const worker = await mediasoup.createWorker({
  rtcMinPort: 20000,  // RTP min port
  rtcMaxPort: 40000,  // RTP max port
});
```

### Thay đổi video codec
Sửa `mediaCodecs` trong `server.js` - hiện tại là H264, có thể đổi sang:
- VP8
- VP9
- AV1

---

## 📊 Cấu trúc File

| File | Mục đích |
|------|---------|
| `server.js` | Main server logic (MediaSoup + WebSocket) |
| `index.html` | Frontend HTML |
| `package.json` | Dependencies |
| `Dockerfile` | Docker image |
| `docker-compose.yml` | Docker Compose config |
| `webpack.config.cjs` | Webpack config (nếu cần build frontend) |
| `.env` | Environment variables |

---

## 🐛 Troubleshooting

### Port đã bị sử dụng
```bash
# Tìm process dùng port 3000
lsof -i :3000

# Kill process
kill -9 <PID>
```

### Firewall block port
- Kiểm tra AWS Security Group inbound rules
- Kiểm tra Linux firewall: `ufw status`
- Kiểm tra iptables: `sudo iptables -L`

### Browser không thể connect
- Kiểm tra `APP_IP` đúng là public IP của server
- Kiểm tra console browser để xem WebSocket connect error
- Kiểm tra server logs: `docker logs web-rtc-server`

---

## 📝 License

MIT - Lamvuon.shop

---

## 🔗 Tham khảo

- [MediaSoup Documentation](https://mediasoup.org/)
- [FFmpeg Documentation](https://ffmpeg.org/documentation.html)
- [WebRTC Spec](https://www.w3.org/TR/webrtc/)
