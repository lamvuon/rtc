FROM node:20-alpine

# Install FFmpeg for streaming
RUN apk add --no-cache ffmpeg

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
# 10000-10100: WebRTC/RTP ports
EXPOSE 3000
EXPOSE 10000-10100/udp
EXPOSE 10000-10100/tcp

# Set environment variables
ENV NODE_ENV=production
ENV APP_IP=0.0.0.0

# Start the application
CMD ["npm", "start"]
