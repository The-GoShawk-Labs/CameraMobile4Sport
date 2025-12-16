# Sport Video Streaming System

A dual-smartphone system for professional sports video streaming with real-time score overlay and multi-platform broadcasting capabilities.

## Overview

This application transforms smartphones into a complete sports broadcasting solution. Using one phone as the primary camera and another as the control interface, it enables live streaming of sports events to YouTube Live and Facebook Live with dynamic score overlays and professional presentation features.

## System Architecture

### Primary Camera Phone
- Main video capture device mounted on tripod/stand
- Connects to control phone via WebRTC/local network
- Streams high-quality video feed
- Supports multiple camera angles (if using multiple camera phones)

### Control Phone (Score UI)
- Real-time score management interface
- Overlay graphics control
- Stream quality monitoring
- Multi-platform broadcast management
- Scoreboard customization

## Key Features

### 📹 Video Streaming
- **Dual-phone setup**: Camera phone + Control phone
- **Multi-platform broadcasting**: Simultaneous streaming to YouTube Live and Facebook Live
- **HD video quality**: Up to 1080p streaming support
- **Low latency**: Real-time video transmission between devices

### 🎯 Score Management
- **Live score overlay**: Dynamic scoreboard on video stream
- **Real-time updates**: Instant score changes visible to viewers
- **Customizable UI**: Team names, colors, logos, and layouts
- **Multiple sports templates**: Basketball, soccer, volleyball, tennis, etc.
- **Timer/clock integration**: Game clock, period/quarter tracking

### 📱 Camera Connection
- **WiFi Direct**: Direct phone-to-phone connection
- **Local network**: Connect via same WiFi network
- **Bluetooth fallback**: Alternative connection method
- **Auto-reconnection**: Maintains stable connection

### 🎨 Graphics & Overlay
- Team logos and colors
- Player statistics
- Game timer and period indicator
- Custom branded graphics
- Lower thirds and announcements

### 🔴 Live Streaming
- YouTube Live API integration
- Facebook Live API integration
- Stream health monitoring
- Bitrate adaptation
- Chat moderation tools

## Tech Stack

**Mobile App**
- React Native / Flutter for cross-platform support
- WebRTC for phone-to-phone video streaming
- FFmpeg for video processing and encoding

**Streaming**
- RTMP protocol for live streaming
- YouTube Live Streaming API
- Facebook Live API
- HLS for adaptive bitrate

**Backend**
- Node.js / Python FastAPI
- WebSocket for real-time score updates
- Redis for caching and pub/sub

**Video Processing**
- OpenCV for overlay rendering
- Hardware encoding (H.264/H.265)
- GPU acceleration support

## System Requirements

### Camera Phone
- Android 8.0+ or iOS 12+
- Minimum 4GB RAM
- Good camera quality (1080p recommended)
- Stable mount/tripod

### Control Phone
- Android 8.0+ or iOS 12+
- Minimum 3GB RAM
- Active internet connection

### Network
- Minimum 5 Mbps upload speed for HD streaming
- WiFi or 4G/5G connection
- Stable network connection

## Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/sport-video-streaming.git

# Install dependencies
cd sport-video-streaming
npm install

# Configure API keys
cp .env.example .env
# Add your YouTube and Facebook API credentials

# Run the app
npm start
```

## Setup Guide

1. **Install app** on both phones (camera and control)
2. **Connect phones** via WiFi Direct or local network
3. **Mount camera phone** on tripod with good view of playing field
4. **Configure stream** settings (YouTube/Facebook credentials)
5. **Customize scoreboard** with team information
6. **Start streaming** and manage scores in real-time

## Configuration

```javascript
// config.js
{
  video: {
    resolution: "1080p",
    fps: 30,
    bitrate: 4000
  },
  streaming: {
    platforms: ["youtube", "facebook"],
    youtube_key: "YOUR_YOUTUBE_KEY",
    facebook_token: "YOUR_FACEBOOK_TOKEN"
  },
  scoreboard: {
    sport: "basketball",
    position: "top-center",
    theme: "modern"
  }
}
```

## Features Roadmap

- [ ] Multi-camera support (3+ phones)
- [ ] Instant replay functionality
- [ ] Cloud recording backup
- [ ] AI-powered highlight detection
- [ ] Picture-in-picture commentary
- [ ] Twitch streaming integration
- [ ] Advanced analytics dashboard
- [ ] Automated camera switching

## Use Cases

- Youth sports leagues
- School athletic events
- Amateur tournaments
- Community sports events
- Training session recording
- Scouting and recruitment
- Family game streaming

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License - see [LICENSE](LICENSE) file for details

## Support

For issues and questions:
- GitHub Issues: [Report bugs](https://github.com/yourusername/sport-video-streaming/issues)
- Documentation: [Full docs](https://docs.example.com)
- Email: support@example.com

## Acknowledgments

Built with ❤️ for sports communities worldwide
