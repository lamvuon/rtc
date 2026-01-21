# rtc

## Thiết lập biến môi trường
Chạy các lệnh sau một lần để lưu vào `~/.bashrc` (tự thay giá trị DOMAIN/EMAIL/EC2_HOST/APP_IP cho môi trường của bạn):

```bash
echo 'export DOMAIN=your-domain-or-ip.example.com' >> ~/.bashrc
echo 'export EMAIL=your-email@example.com' >> ~/.bashrc

echo 'export EC2_HOST=ubuntu@your-public-ip-or-host' >> ~/.bashrc
echo 'export APP_IP=your-public-ip' >> ~/.bashrc

source ~/.bashrc
```

Sau khi thay đổi, mở terminal mới hoặc chạy `source ~/.bashrc` trước khi dùng các script deploy/stream.

## Chuẩn bị media mẫu
- Tải video mẫu về máy local và đặt tên `video.mp4` (dùng cho script stream-from-pc):
	```bash
	curl -L "https://sample-videos.com/video321/mp4/720/big_buck_bunny_720p_1mb.mp4" -o video.mp4
	```

- Tải video mẫu trên EC2 và đặt tên `test-video.mp4` (dùng cho script stream chạy trên EC2):
	```bash
	ssh "$EC2_HOST" "curl -L 'https://sample-videos.com/video321/mp4/720/big_buck_bunny_720p_1mb.mp4' -o ~/test-video.mp4"
	```

Thay URL video nếu bạn muốn dùng nguồn khác; chỉ cần giữ đúng tên file theo từng script.

## Cài đặt và chạy server
```bash
npm install        # hoặc pnpm install / yarn install
npm start          # chạy server (port 3000)
```

## Deploy / đồng bộ code
- Deploy đầy đủ: `./deploy.sh` (rsync + cài đặt + pm2).
- Chỉ rsync code: `./push.sh`.
- Cấu hình Nginx + SSL từ máy local: `./run-setup-nginx-ssl-remote.sh <domain> <email>` (mặc định lấy từ env nếu không truyền).

### Gợi ý domain với sslip.io
- Nếu chưa có domain, có thể dùng tạm sslip.io: với IP `A.B.C.D`, dùng domain `A-B-C-D.sslip.io`.
- Ví dụ IP `1.2.3.4` → domain `1-2-3-4.sslip.io`.
- Cập nhật env:
	```bash
	echo 'export DOMAIN=1-2-3-4.sslip.io' >> ~/.bashrc
	source ~/.bashrc
	```

Nếu đổi IP EC2, hãy đổi lại DOMAIN cho khớp.

## Streaming
- Stream từ PC lên EC2 qua RTP (dùng `video.mp4` local): `./stream-from-pc.sh`.
- Stream FFmpeg chạy trực tiếp trên EC2 (dùng `~/test-video.mp4`): `./stream.sh`.

Đảm bảo đã set biến môi trường và chuẩn bị media trước khi chạy các script trên.