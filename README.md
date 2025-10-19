# AetherTalk - Enterprise WhatsApp-like Messaging Platform

AetherTalk is a comprehensive, enterprise-grade messaging platform built with Erlang/OTP that provides all the features and capabilities of WhatsApp with additional enterprise features. It's designed for high scalability, reliability, and performance with support for real-time messaging, voice/video calls, media sharing, and advanced features like real-time translation.

## 🚀 Features

### Core Messaging
- ✅ Real-time messaging with WebSocket connections
- ✅ Message delivery status (sent, delivered, read)
- ✅ Message encryption and security
- ✅ Message reactions and replies
- ✅ Message editing and deletion
- ✅ Typing indicators and presence system
- ✅ Chat archiving, pinning, and muting

### Media & Files
- ✅ Image, video, and audio sharing
- ✅ File upload and sharing
- ✅ Media compression and thumbnails
- ✅ Media encryption for security

### Voice & Video Calls
- ✅ High-quality voice calls
- ✅ HD video calls
- ✅ WebRTC integration
- ✅ Call signaling and management
- ✅ STUN/TURN server support

### Advanced Features
- ✅ Real-time translation service
- ✅ Language detection
- ✅ Streaming translation for calls
- 🔄 Group management (in development)
- 🔄 Status/Stories (planned)
- 🔄 Disappearing messages (planned)
- 🔄 Polls and location sharing (planned)

### Enterprise Features
- ✅ User management and authentication
- ✅ Contact management
- ✅ Push notifications
- ✅ Email notifications
- 🔄 Business accounts (planned)
- 🔄 API access and webhooks (planned)
- 🔄 Analytics and compliance (planned)

### Infrastructure
- ✅ PostgreSQL database with connection pooling
- ✅ Redis for caching and real-time features
- ✅ Horizontal scaling support
- ✅ Health checks and monitoring
- ✅ Rate limiting and security
- ✅ Comprehensive logging

## 🏗️ Architecture

AetherTalk is built using Erlang/OTP's actor model with a modular, scalable architecture:

```
aethertalk_app
├── aethertalk_sup (Main Supervisor)
│   ├── aethertalk_db_sup (Database Supervisor)
│   │   ├── Database Workers (PostgreSQL)
│   │   └── Redis Workers
│   ├── aethertalk_core_sup (Core Services)
│   │   ├── User Manager
│   │   ├── Message Router
│   │   ├── Presence Manager
│   │   ├── Media Processor
│   │   ├── Call Manager
│   │   ├── Translation Service
│   │   └── Notification Service
│   └── aethertalk_api_sup (API Layer)
│       ├── HTTP/REST API
│       ├── WebSocket Manager
│       └── WebSocket Handler
```

### Key Components

- **Message Router**: Handles message routing, delivery, and persistence
- **WebSocket Manager**: Manages real-time connections and broadcasting
- **Presence Manager**: Tracks user presence and typing indicators
- **Media Processor**: Handles media upload, compression, and processing
- **Call Manager**: Manages voice/video calls and WebRTC signaling
- **Translation Service**: Provides real-time translation capabilities
- **User Manager**: Handles authentication, contacts, and user settings

## 📋 Prerequisites

- Erlang/OTP 24+ 
- PostgreSQL 13+
- Redis 6+
- Rebar3 (Erlang build tool)

## 🛠️ Installation

1. **Clone the repository:**
   ```bash
   git clone <repository-url>
   cd aethertalk
   ```

2. **Install dependencies:**
   ```bash
   rebar3 deps
   ```

3. **Set up PostgreSQL database:**
   ```sql
   CREATE DATABASE aethertalk;
   CREATE USER aethertalk WITH PASSWORD 'your_password';
   GRANT ALL PRIVILEGES ON DATABASE aethertalk TO aethertalk;
   ```

4. **Configure the application:**
   Edit `config/sys.config` with your database and Redis settings:
   ```erlang
   [
     {aethertalk, [
       {database, [
         {host, "localhost"},
         {port, 5432},
         {database, "aethertalk"},
         {username, "aethertalk"},
         {password, "your_password"}
       ]},
       {redis, [
         {host, "localhost"},
         {port, 6379}
       ]},
       {http_port, 8080},
       {websocket_port, 8081}
     ]}
   ].
   ```

5. **Initialize the database:**
   ```bash
   # Run the database schema creation script
   psql -U aethertalk -d aethertalk -f priv/schema.sql
   ```

6. **Compile the application:**
   ```bash
   rebar3 compile
   ```

## 🚀 Running the Application

### Development Mode
```bash
rebar3 shell
```

### Production Mode
```bash
rebar3 release
_build/default/rel/aethertalk/bin/aethertalk start
```

The application will start:
- HTTP API on port 8080
- WebSocket connections on port 8081
- Health check endpoint: `http://localhost:8080/health`

## 📡 API Endpoints

### Authentication
- `POST /api/v1/auth/register` - User registration
- `POST /api/v1/auth/login` - User login
- `POST /api/v1/auth/logout` - User logout
- `POST /api/v1/auth/refresh` - Refresh JWT token

### Users
- `GET /api/v1/users/profile` - Get user profile
- `PUT /api/v1/users/profile` - Update user profile
- `POST /api/v1/users/contacts` - Add contact
- `GET /api/v1/users/contacts` - Get contacts

### Messages
- `POST /api/v1/messages` - Send message
- `GET /api/v1/messages/:chat_id` - Get chat messages
- `PUT /api/v1/messages/:id` - Edit message
- `DELETE /api/v1/messages/:id` - Delete message

### Chats
- `GET /api/v1/chats` - Get user chats
- `POST /api/v1/chats` - Create chat
- `PUT /api/v1/chats/:id/archive` - Archive chat
- `PUT /api/v1/chats/:id/pin` - Pin chat

### Calls
- `POST /api/v1/calls` - Initiate call
- `PUT /api/v1/calls/:id/end` - End call
- `POST /api/v1/calls/:id/signal` - WebRTC signaling

### Media
- `POST /api/v1/media/upload` - Upload media file
- `GET /api/v1/media/:id` - Get media file

## 🔌 WebSocket API

Connect to `ws://localhost:8081/ws` with authentication token.

### Message Types

#### Authentication
```json
{
  "type": "auth",
  "token": "jwt_token_here"
}
```

#### Send Message
```json
{
  "type": "send_message",
  "chat_id": "chat_uuid",
  "content": "Hello, world!",
  "message_type": "text"
}
```

#### Typing Indicator
```json
{
  "type": "typing",
  "chat_id": "chat_uuid",
  "is_typing": true
}
```

#### Call Signaling
```json
{
  "type": "call_signal",
  "call_id": "call_uuid",
  "signal_type": "offer",
  "signal": { "sdp": "..." }
}
```

## 🗄️ Database Schema

The application uses PostgreSQL with the following main tables:

- `users` - User accounts and profiles
- `chats` - Chat rooms and conversations
- `messages` - All messages with content and metadata
- `message_reactions` - Message reactions and emojis
- `contacts` - User contact relationships
- `calls` - Voice/video call records
- `media_files` - Uploaded media and files
- `notifications` - Push and email notifications
- `user_settings` - User preferences and settings

## 🔧 Configuration

### Environment Variables
- `AETHERTALK_DB_HOST` - Database host
- `AETHERTALK_DB_PORT` - Database port
- `AETHERTALK_DB_NAME` - Database name
- `AETHERTALK_DB_USER` - Database username
- `AETHERTALK_DB_PASS` - Database password
- `AETHERTALK_REDIS_HOST` - Redis host
- `AETHERTALK_REDIS_PORT` - Redis port
- `AETHERTALK_HTTP_PORT` - HTTP API port
- `AETHERTALK_WS_PORT` - WebSocket port

### Application Configuration
Edit `config/sys.config` for detailed configuration options including:
- Database connection settings
- Redis configuration
- JWT secret keys
- Media upload settings
- Translation service API keys
- Push notification credentials

## 🧪 Testing

```bash
# Run unit tests
rebar3 eunit

# Run common tests
rebar3 ct

# Run all tests
rebar3 do eunit, ct
```

## 📊 Monitoring

### Health Checks
- `GET /health` - Application health status
- `GET /metrics` - Application metrics

### Logging
The application uses structured logging with different levels:
- Error logs for system errors
- Info logs for important events
- Debug logs for development

Logs are written to:
- Console (development)
- Files in `log/` directory (production)

## 🚀 Deployment

### Docker
```bash
# Build Docker image
docker build -t aethertalk .

# Run container
docker run -d \
  -p 8080:8080 \
  -p 8081:8081 \
  -e AETHERTALK_DB_HOST=your_db_host \
  -e AETHERTALK_REDIS_HOST=your_redis_host \
  aethertalk
```

### Clustering
AetherTalk supports horizontal scaling through Erlang distribution:

```bash
# Start first node
_build/default/rel/aethertalk/bin/aethertalk start -name aethertalk1@node1.example.com

# Start second node and connect to cluster
_build/default/rel/aethertalk/bin/aethertalk start -name aethertalk2@node2.example.com
```

## 🔒 Security

- JWT-based authentication
- Password hashing with bcrypt
- Message encryption
- Rate limiting
- Input validation and sanitization
- CORS protection
- Security headers

## 🌐 Translation Service

AetherTalk includes real-time translation capabilities:
- Automatic language detection
- Text message translation
- Real-time call translation (streaming)
- Support for 100+ languages
- High accuracy translation models

## 📱 Client Integration

### WebSocket Client Example (JavaScript)
```javascript
const ws = new WebSocket('ws://localhost:8081/ws');

// Authenticate
ws.send(JSON.stringify({
  type: 'auth',
  token: 'your_jwt_token'
}));

// Send message
ws.send(JSON.stringify({
  type: 'send_message',
  chat_id: 'chat-uuid',
  content: 'Hello!',
  message_type: 'text'
}));

// Handle incoming messages
ws.onmessage = (event) => {
  const message = JSON.parse(event.data);
  console.log('Received:', message);
};
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🆘 Support

For support and questions:
- Create an issue on GitHub
- Check the documentation
- Review the API examples

## 🗺️ Roadmap

### Phase 1 (Current)
- ✅ Core messaging functionality
- ✅ Real-time communication
- ✅ Voice/video calls
- ✅ Media handling
- ✅ Translation service

### Phase 2 (Next)
- 🔄 Group management
- 🔄 Advanced security features
- 🔄 Enterprise features
- 🔄 Comprehensive testing

### Phase 3 (Future)
- 🔄 Mobile SDKs
- 🔄 Desktop applications
- 🔄 Advanced analytics
- 🔄 AI-powered features

---

**AetherTalk** - Built with ❤️ using Erlang/OTP for enterprise-grade messaging.
