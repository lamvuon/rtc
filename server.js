import express from "express";
import { createServer } from "http";
import { WebSocketServer } from "ws";
import mediasoup from "mediasoup";
import dotenv from "dotenv";

dotenv.config();

const APP_IP = process.env.APP_IP || "0.0.0.0";
const APP_PORT = Number(process.env.APP_PORT || 3000);

const app = express();

// Serve static files
app.use(express.static('.'));

const httpServer = createServer(app);
const wss = new WebSocketServer({ server: httpServer });

const worker = await mediasoup.createWorker();
const router = await worker.createRouter({
  mediaCodecs: [
    {
      kind: "video",
      mimeType: "video/H264",
      clockRate: 90000,
      parameters: {
        "packetization-mode": 1
      }
    },
    {
      kind: "audio",
      mimeType: "audio/opus",
      clockRate: 48000,
      channels: 2
    }
  ]
});

// Video transport - receives RTP from PC
const videoTransport = await router.createPlainTransport({
  listenIp: {
    ip: '0.0.0.0',
    announcedIp: APP_IP  // EC2 Public IP
  },
  rtcpMux: false,  // QUAN TRỌNG: phải false để nhận RTP từ PC
  comedia: true    // Tự động detect địa chỉ nguồn
});

console.log("🔥 Video RTP port:", videoTransport.tuple.localPort);

const videoProducer = await videoTransport.produce({
  kind: "video",
  rtpParameters: {
    codecs: [{
      mimeType: "video/H264",
      payloadType: 96,
      clockRate: 90000,
      parameters: {
        "packetization-mode": 1,
        "profile-level-id": "42e01f"  // Baseline profile
      }
    }],
    encodings: [{ ssrc: 11111111 }]
  }
});

// Audio transport - receives RTP from PC
const audioTransport = await router.createPlainTransport({
  listenIp: {
    ip: '0.0.0.0',
    announcedIp: APP_IP  // EC2 Public IP
  },
  rtcpMux: false,  // QUAN TRỌNG: phải false để nhận RTP từ PC
  comedia: true    // Tự động detect địa chỉ nguồn
});

console.log("🔊 Audio RTP port:", audioTransport.tuple.localPort);

const audioProducer = await audioTransport.produce({
  kind: "audio",
  rtpParameters: {
    codecs: [{
      mimeType: "audio/opus",
      payloadType: 97,
      clockRate: 48000,
      channels: 2
    }],
    encodings: [{ ssrc: 22222222 }]
  }
});

console.log("✅ Producers created");
console.log("   Video: H264, PayloadType: 96");
console.log("   Audio: Opus, PayloadType: 97");

console.log("Mediasoup ready");
console.log("⚠️ AnnouncedIp set to:", APP_IP);

// WebSocket signaling - Browser communication
wss.on("connection", (ws) => {
  console.log("Client connected");
  
  let clientTransport = null;
  let videoConsumer = null;
  let audioConsumer = null;
  
  // Keepalive ping every 30 seconds
  const keepAliveInterval = setInterval(() => {
    if (ws.readyState === ws.OPEN) {
      ws.ping();
    }
  }, 30000);
  
  ws.on('pong', () => {
    // Client responded to ping
  });

  ws.on("message", async (message) => {
    const data = JSON.parse(message);

    switch (data.type) {
      case "getRouterRtpCapabilities":
        // Send router capabilities to browser
        ws.send(JSON.stringify({
          type: "routerRtpCapabilities",
          data: router.rtpCapabilities
        }));
        break;
      
      case "getProducers":
        // Send available producer IDs
        ws.send(JSON.stringify({
          type: "producers",
          data: {
            videoProducerId: videoProducer.id,
            audioProducerId: audioProducer.id
          }
        }));
        break;

      case "createTransport":
        // Create a new WebRTC transport for this client
        clientTransport = await router.createWebRtcTransport({
          listenIps: [{
            ip: "0.0.0.0",
            announcedIp: APP_IP
          }],
          enableUdp: true,
          enableTcp: true,
          preferUdp: true
        });
        
        console.log("✅ Created transport for client:", clientTransport.id);
        
        // Send transport parameters to browser
        ws.send(JSON.stringify({
          type: "transportCreated",
          data: {
            id: clientTransport.id,
            iceParameters: clientTransport.iceParameters,
            iceCandidates: clientTransport.iceCandidates,
            dtlsParameters: clientTransport.dtlsParameters
          }
        }));
        break;

      case "connectTransport":
        if (!clientTransport) {
          console.error("❌ No transport for client");
          return;
        }
        
        // Connect transport with client DTLS parameters
        await clientTransport.connect({
          dtlsParameters: data.dtlsParameters
        });
        console.log("✅ Transport connected for client");
        ws.send(JSON.stringify({ type: "transportConnected" }));
        break;

      case "consume":
        if (!clientTransport) {
          console.error("❌ No transport for client");
          return;
        }
        
        const producerId = data.producerId;
        const producer = producerId === videoProducer.id ? videoProducer : audioProducer;
        
        // Create consumer for video or audio
        const consumer = await clientTransport.consume({
          producerId: producerId,
          rtpCapabilities: data.rtpCapabilities,
          paused: false
        });
        
        if (consumer.kind === 'video') {
          videoConsumer = consumer;
          console.log("✅ Video consumer created:", consumer.id);
        } else {
          audioConsumer = consumer;
          console.log("✅ Audio consumer created:", consumer.id);
        }

        ws.send(JSON.stringify({
          type: "consumed",
          data: {
            id: consumer.id,
            producerId: producerId,
            kind: consumer.kind,
            rtpParameters: consumer.rtpParameters
          }
        }));
        break;
    }
  });
  
  // Cleanup when client disconnects
  ws.on("close", async () => {
    console.log("Client disconnected");
    
    clearInterval(keepAliveInterval);
    
    if (videoConsumer) {
      videoConsumer.close();
      console.log("✅ Video consumer closed");
    }
    
    if (audioConsumer) {
      audioConsumer.close();
      console.log("✅ Audio consumer closed");
    }
    
    if (clientTransport) {
      clientTransport.close();
      console.log("✅ Transport closed");
    }
  });
});

httpServer.listen(APP_PORT, () => {
  console.log(`🚀 HTTP Server listening on port ${APP_PORT}`);
});
