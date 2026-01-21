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