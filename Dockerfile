FROM node:20-alpine

# Install FFmpeg and bash for streaming
RUN apk add --no-cache ffmpeg bash

# Set working directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm install --production

# Copy application files
COPY . .

# Expose ports
# 3000: HTTP server
# 20000-40000: WebRTC/RTP ports (matching mediasoup config)
EXPOSE 3000
EXPOSE 20000-40000/udp
EXPOSE 20000-40000/tcp

# Set environment variables
ENV NODE_ENV=production
ENV APP_IP=0.0.0.0

# Make startup script executable
RUN chmod +x /app/docker-start.sh || true

# Start the application
CMD ["/app/docker-start.sh"]
