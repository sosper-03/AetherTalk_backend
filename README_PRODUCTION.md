# AetherTalk Backend - Production Deployment Guide

## 🚀 Enterprise-Ready WhatsApp-like Backend

AetherTalk is a comprehensive, enterprise-grade backend solution that provides all the features of WhatsApp and more, including:

- **Multi-tenant Architecture** with complete tenant isolation
- **Horizontal Scaling** with clustering support
- **HD Voice & Video Calls** with WebRTC
- **Real-time Translation** with multiple providers
- **End-to-End Encryption** for secure messaging
- **High Availability** with load balancing and failover
- **Production-Ready** with monitoring, logging, and health checks

## 📋 Table of Contents

- [Features](#features)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Production Deployment](#production-deployment)
- [Configuration](#configuration)
- [Scaling](#scaling)
- [Monitoring](#monitoring)
- [Security](#security)
- [API Documentation](#api-documentation)
- [Troubleshooting](#troubleshooting)

## ✨ Features

### Core Messaging Features
- ✅ Real-time messaging with WebSocket support
- ✅ Group chats with admin controls
- ✅ File sharing (images, videos, documents, audio)
- ✅ Message reactions and replies
- ✅ Message editing and deletion
- ✅ Typing indicators and read receipts
- ✅ Message search and history
- ✅ Disappearing messages
- ✅ Message forwarding
- ✅ Status/Stories functionality
- ✅ Polls and surveys
- ✅ Location sharing

### Advanced Communication
- ✅ HD Voice calls with noise cancellation
- ✅ HD Video calls with screen sharing
- ✅ Group voice and video calls
- ✅ Call recording and playback
- ✅ Real-time translation during calls
- ✅ Voice messages with transcription

### Enterprise Features
- ✅ Multi-tenant architecture with complete isolation
- ✅ Horizontal scaling with automatic load balancing
- ✅ End-to-end encryption (E2EE)
- ✅ Two-factor authentication (2FA)
- ✅ Single Sign-On (SSO) integration
- ✅ Admin dashboard and analytics
- ✅ Audit logging and compliance
- ✅ Rate limiting and DDoS protection
- ✅ Backup and disaster recovery

### Translation & Accessibility
- ✅ Real-time message translation
- ✅ Voice message translation
- ✅ Multiple translation providers (Google, Azure, AWS, LibreTranslate)
- ✅ Language detection
- ✅ Voice-to-text transcription
- ✅ Text-to-speech synthesis

## 🏗️ Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Load Balancer │    │   Load Balancer │    │   Load Balancer │
│     (Nginx)     │    │     (Nginx)     │    │     (Nginx)     │
└─────────┬───────┘    └─────────┬───────┘    └─────────┬───────┘
          │                      │                      │
          └──────────────────────┼──────────────────────┘
                                 │
    ┌────────────────────────────┼────────────────────────────┐
    │                            │                            │
┌───▼────┐              ┌────────▼────────┐              ┌───▼────┐
│AetherTalk│              │   AetherTalk    │              │AetherTalk│
│Instance 1│              │   Instance 2    │              │Instance 3│
└────┬─────┘              └─────────┬───────┘              └────┬────┘
     │                              │                           │
     └──────────────────────────────┼───────────────────────────┘
                                    │
              ┌─────────────────────┼─────────────────────┐
              │                     │                     │
         ┌────▼────┐          ┌─────▼─────┐         ┌────▼────┐
         │PostgreSQL│          │   Redis   │         │  TURN   │
         │Cluster  │          │ Cluster   │         │ Server  │
         └─────────┘          └───────────┘         └─────────┘
```

### Technology Stack
- **Backend**: Erlang/OTP 27 with high concurrency support
- **Database**: PostgreSQL 15 with multi-tenant row-level security
- **Cache**: Redis 7 for sessions and real-time data
- **WebRTC**: Native WebRTC implementation with TURN/STUN servers
- **Load Balancer**: Nginx with SSL termination and rate limiting
- **Containerization**: Docker with multi-stage builds
- **Orchestration**: Docker Compose with health checks
- **Monitoring**: Prometheus + Grafana + ELK Stack

## 📋 Prerequisites

### System Requirements
- **CPU**: Minimum 4 cores, Recommended 8+ cores
- **RAM**: Minimum 8GB, Recommended 16GB+
- **Storage**: Minimum 100GB SSD, Recommended 500GB+ NVMe
- **Network**: Minimum 100Mbps, Recommended 1Gbps+

### Software Requirements
- Docker 20.10+
- Docker Compose 2.0+
- Git 2.30+
- OpenSSL 1.1.1+

### Network Requirements
- Ports 80, 443 (HTTP/HTTPS)
- Ports 8080, 8443 (Application)
- Ports 3478, 49152-65535 (WebRTC/TURN)
- Port 5432 (PostgreSQL)
- Port 6379 (Redis)

## 🚀 Quick Start

### 1. Clone the Repository
```bash
git clone https://github.com/your-org/aethertalk-backend.git
cd aethertalk-backend
```

### 2. Configure Environment
```bash
cp .env.example .env
# Edit .env with your configuration
nano .env
```

### 3. Deploy with One Command
```bash
./deploy.sh deploy
```

### 4. Verify Deployment
```bash
curl -f http://localhost:8080/api/health
```

## 🏭 Production Deployment

### Step 1: Server Preparation

#### Ubuntu/Debian
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Install additional tools
sudo apt install -y git openssl curl wget htop
```

#### CentOS/RHEL
```bash
# Update system
sudo yum update -y

# Install Docker
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
sudo yum install -y docker-ce docker-ce-cli containerd.io
sudo systemctl start docker
sudo systemctl enable docker
sudo usermod -aG docker $USER

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose
```

### Step 2: SSL Certificate Setup

#### Option A: Let's Encrypt (Recommended for Production)
```bash
# Install Certbot
sudo apt install -y certbot

# Generate certificates
sudo certbot certonly --standalone -d yourdomain.com -d *.yourdomain.com

# Copy certificates
sudo cp /etc/letsencrypt/live/yourdomain.com/fullchain.pem ./nginx/ssl/cert.pem
sudo cp /etc/letsencrypt/live/yourdomain.com/privkey.pem ./nginx/ssl/key.pem
sudo chown $USER:$USER ./nginx/ssl/*.pem
```

#### Option B: Self-Signed (Development/Testing)
```bash
# Generate self-signed certificates
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout ./nginx/ssl/key.pem \
    -out ./nginx/ssl/cert.pem \
    -subj "/C=US/ST=State/L=City/O=AetherTalk/CN=yourdomain.com"
```

### Step 3: Environment Configuration

Create and configure your `.env` file:

```bash
cp .env.example .env
```

**Critical settings to change:**
```env
# Security - MUST CHANGE THESE
ERLANG_COOKIE=your_super_secure_random_string_here
JWT_SECRET=your_jwt_secret_minimum_32_characters_long
ENCRYPTION_KEY=your_32_character_encryption_key_here
DB_PASSWORD=your_very_secure_database_password
REDIS_PASSWORD=your_secure_redis_password

# Domain configuration
CORS_ORIGINS=https://yourdomain.com,https://app.yourdomain.com

# Translation services (optional)
GOOGLE_TRANSLATE_API_KEY=your_google_api_key
AZURE_TRANSLATOR_API_KEY=your_azure_api_key

# WebRTC configuration
TURN_SERVER_URL=turn:your-turn-server.com:3478
TURN_USERNAME=your_turn_username
TURN_PASSWORD=your_turn_password
```

### Step 4: Deploy

```bash
# Make deployment script executable
chmod +x deploy.sh

# Run full deployment
./deploy.sh deploy
```

### Step 5: Verify Deployment

```bash
# Check service status
./deploy.sh status

# Run health checks
./deploy.sh health

# View logs
./deploy.sh logs
```

## ⚙️ Configuration

### Database Configuration

The application uses PostgreSQL with multi-tenant support. Each tenant has isolated data through Row Level Security (RLS).

```sql
-- Example tenant creation
INSERT INTO tenants (id, name, slug, domain, plan, created_at) 
VALUES (
    gen_random_uuid(),
    'Enterprise Corp',
    'enterprise-corp',
    'enterprise.yourdomain.com',
    'enterprise',
    NOW()
);
```

### Redis Configuration

Redis is used for:
- Session storage
- Real-time message caching
- Pub/Sub for WebSocket events
- Rate limiting counters
- Translation cache

### WebRTC Configuration

For production WebRTC calls, you need:

1. **STUN Servers** (for NAT traversal)
2. **TURN Servers** (for relay when direct connection fails)

```env
# Public STUN servers (free but limited)
STUN_SERVERS=stun:stun.l.google.com:19302

# Your own TURN server (recommended for production)
TURN_SERVER_URL=turn:your-turn-server.com:3478
TURN_USERNAME=your_username
TURN_PASSWORD=your_password
```

## 📈 Scaling

### Horizontal Scaling

#### Add More Application Instances

1. **Update docker-compose.yml**:
```yaml
services:
  aethertalk-2:
    build: .
    container_name: aethertalk-backend-2
    environment:
      - NODE_NAME=aethertalk2@aethertalk-2
    # ... other config

  aethertalk-3:
    build: .
    container_name: aethertalk-backend-3
    environment:
      - NODE_NAME=aethertalk3@aethertalk-3
    # ... other config
```

2. **Update Nginx upstream**:
```nginx
upstream aethertalk_backend {
    least_conn;
    server aethertalk:8080 max_fails=3 fail_timeout=30s;
    server aethertalk-2:8080 max_fails=3 fail_timeout=30s;
    server aethertalk-3:8080 max_fails=3 fail_timeout=30s;
}
```

#### Database Scaling

1. **Read Replicas**:
```yaml
postgres-replica:
  image: postgres:15-alpine
  environment:
    - POSTGRES_MASTER_SERVICE=postgres
    - POSTGRES_REPLICA_USER=replica
    - POSTGRES_REPLICA_PASSWORD=replica_password
```

2. **Connection Pooling**:
```yaml
pgbouncer:
  image: pgbouncer/pgbouncer:latest
  environment:
    - DATABASES_HOST=postgres
    - DATABASES_PORT=5432
    - POOL_MODE=transaction
    - MAX_CLIENT_CONN=1000
```

#### Redis Clustering

```yaml
redis-cluster:
  image: redis:7-alpine
  command: redis-server --cluster-enabled yes --cluster-config-file nodes.conf
  volumes:
    - redis_cluster_data:/data
```

### Vertical Scaling

#### Resource Limits
```yaml
services:
  aethertalk:
    deploy:
      resources:
        limits:
          cpus: '4.0'
          memory: 8G
        reservations:
          cpus: '2.0'
          memory: 4G
```

#### Performance Tuning
```env
# Erlang VM tuning
ERL_MAX_PROCESSES=1048576
ERL_MAX_PORTS=65536
ERL_ASYNC_THREADS=64

# Database tuning
DB_POOL_SIZE=50
DB_MAX_OVERFLOW=20
DB_TIMEOUT=30000

# Redis tuning
REDIS_POOL_SIZE=20
REDIS_TIMEOUT=5000
```

## 📊 Monitoring

### Health Checks

The application provides comprehensive health checks:

```bash
# Application health
curl http://localhost:8080/api/health

# Database health
curl http://localhost:8080/api/health/database

# Redis health
curl http://localhost:8080/api/health/redis

# Cluster health
curl http://localhost:8080/api/health/cluster
```

### Metrics

Prometheus metrics are available at:
```
http://localhost:9100/metrics
```

Key metrics include:
- Request rate and latency
- Database connection pool usage
- Redis cache hit/miss ratio
- WebSocket connection count
- Message throughput
- Translation API usage
- File upload/download rates

### Logging

Logs are structured in JSON format and include:
- Request/response logs
- Error logs with stack traces
- Security events
- Performance metrics
- Audit trails

```bash
# View application logs
docker logs aethertalk-backend

# View all logs
./deploy.sh logs

# Follow logs in real-time
docker-compose logs -f
```

### Alerting

Set up alerts for:
- High error rates (>5%)
- High response times (>2s)
- Database connection failures
- Redis connection failures
- Disk space usage (>80%)
- Memory usage (>85%)
- CPU usage (>80%)

## 🔒 Security

### Authentication & Authorization

1. **JWT Tokens** with configurable expiry
2. **Refresh Tokens** for seamless user experience
3. **Multi-Factor Authentication** (MFA) support
4. **Role-Based Access Control** (RBAC)
5. **API Key Authentication** for service-to-service

### Encryption

1. **End-to-End Encryption** for messages
2. **TLS 1.3** for transport security
3. **AES-256-GCM** for data at rest
4. **Key rotation** support
5. **Perfect Forward Secrecy**

### Security Headers

Nginx is configured with security headers:
```nginx
add_header X-Frame-Options DENY;
add_header X-Content-Type-Options nosniff;
add_header X-XSS-Protection "1; mode=block";
add_header Strict-Transport-Security "max-age=31536000; includeSubDomains; preload";
add_header Content-Security-Policy "default-src 'self'";
```

### Rate Limiting

Multiple rate limiting layers:
1. **Nginx** - Network level
2. **Application** - API level
3. **Database** - Query level
4. **Redis** - Cache level

### Audit Logging

All security-relevant events are logged:
- Authentication attempts
- Authorization failures
- Data access
- Configuration changes
- Admin actions

## 📚 API Documentation

### Authentication Endpoints

```http
POST /api/auth/register
POST /api/auth/login
POST /api/auth/logout
POST /api/auth/refresh
GET  /api/auth/validate
POST /api/auth/forgot-password
POST /api/auth/reset-password
```

### User Management

```http
GET    /api/users/profile
PUT    /api/users/profile
GET    /api/users/search
GET    /api/users/:id
POST   /api/users/avatar
DELETE /api/users/avatar
```

### Chat Management

```http
GET    /api/chats
POST   /api/chats
GET    /api/chats/:id
PUT    /api/chats/:id
DELETE /api/chats/:id
POST   /api/chats/:id/participants
DELETE /api/chats/:id/participants/:userId
POST   /api/chats/:id/leave
```

### Messaging

```http
GET    /api/chats/:id/messages
POST   /api/chats/:id/messages
PUT    /api/messages/:id
DELETE /api/messages/:id
POST   /api/messages/:id/reactions
POST   /api/chats/:id/typing
```

### File Management

```http
POST   /api/files/upload
GET    /api/files/:id
DELETE /api/files/:id
GET    /api/files/:id/thumbnail
```

### Voice & Video Calls

```http
POST   /api/calls/initiate
POST   /api/calls/:id/answer
POST   /api/calls/:id/decline
POST   /api/calls/:id/end
POST   /api/calls/:id/mute
POST   /api/calls/:id/unmute
GET    /api/calls/ice-servers
```

### Translation

```http
POST   /api/translate/text
POST   /api/translate/detect
GET    /api/translate/languages
POST   /api/translate/auto-enable
POST   /api/translate/auto-disable
```

### Admin APIs

```http
GET    /api/admin/stats
GET    /api/admin/users
GET    /api/admin/tenants
POST   /api/admin/tenants
GET    /api/admin/health
GET    /api/admin/metrics
```

### WebSocket Events

```javascript
// Connection
ws://localhost:8080/ws?token=JWT_TOKEN

// Events
{
  "type": "message_received",
  "data": { "chat_id": "...", "message": {...} }
}

{
  "type": "user_typing",
  "data": { "chat_id": "...", "user_id": "..." }
}

{
  "type": "call_incoming",
  "data": { "call_id": "...", "caller": {...} }
}
```

## 🔧 Troubleshooting

### Common Issues

#### 1. Application Won't Start

```bash
# Check logs
docker logs aethertalk-backend

# Check database connection
docker exec aethertalk-postgres pg_isready -U aethertalk

# Check Redis connection
docker exec aethertalk-redis redis-cli ping

# Restart services
./deploy.sh restart
```

#### 2. Database Connection Issues

```bash
# Check database status
docker exec aethertalk-postgres pg_isready -U aethertalk -d aethertalk

# Check database logs
docker logs aethertalk-postgres

# Reset database password
docker exec -it aethertalk-postgres psql -U postgres -c "ALTER USER aethertalk PASSWORD 'new_password';"
```

#### 3. WebRTC Calls Not Working

```bash
# Check TURN server connectivity
telnet your-turn-server.com 3478

# Verify STUN/TURN configuration
curl http://localhost:8080/api/calls/ice-servers

# Check firewall rules
sudo ufw status
```

#### 4. High Memory Usage

```bash
# Check memory usage
docker stats

# Tune Erlang VM
export ERL_MAX_PROCESSES=262144
export ERL_ASYNC_THREADS=32

# Restart with new limits
./deploy.sh restart
```

#### 5. SSL Certificate Issues

```bash
# Check certificate validity
openssl x509 -in ./nginx/ssl/cert.pem -text -noout

# Renew Let's Encrypt certificate
sudo certbot renew

# Test SSL configuration
curl -I https://yourdomain.com
```

### Performance Optimization

#### 1. Database Optimization

```sql
-- Add indexes for better performance
CREATE INDEX CONCURRENTLY idx_messages_chat_id_created_at ON messages(chat_id, created_at DESC);
CREATE INDEX CONCURRENTLY idx_users_email_hash ON users USING hash(email);

-- Analyze query performance
EXPLAIN ANALYZE SELECT * FROM messages WHERE chat_id = 'uuid' ORDER BY created_at DESC LIMIT 50;
```

#### 2. Redis Optimization

```bash
# Monitor Redis performance
docker exec aethertalk-redis redis-cli --latency-history

# Check memory usage
docker exec aethertalk-redis redis-cli info memory

# Optimize Redis configuration
echo "maxmemory-policy allkeys-lru" >> redis.conf
```

#### 3. Application Optimization

```bash
# Monitor application metrics
curl http://localhost:9100/metrics | grep aethertalk

# Profile memory usage
docker exec aethertalk-backend observer:start().

# Check process count
docker exec aethertalk-backend ps aux | wc -l
```

### Backup and Recovery

#### 1. Database Backup

```bash
# Create backup
./deploy.sh backup

# Manual database backup
docker exec aethertalk-postgres pg_dump -U aethertalk aethertalk > backup.sql

# Restore from backup
docker exec -i aethertalk-postgres psql -U aethertalk aethertalk < backup.sql
```

#### 2. File Backup

```bash
# Backup uploads
tar -czf uploads_backup.tar.gz uploads/

# Backup configuration
tar -czf config_backup.tar.gz .env nginx/ docker-compose.yml
```

#### 3. Disaster Recovery

```bash
# Full system restore
./deploy.sh rollback

# Restore from specific backup
BACKUP_DATE=20231201_120000
docker exec -i aethertalk-postgres psql -U aethertalk aethertalk < backups/backup_$BACKUP_DATE/database.sql
```

## 📞 Support

### Getting Help

1. **Documentation**: Check this README and inline code comments
2. **Issues**: Create an issue on GitHub with detailed information
3. **Discussions**: Join our community discussions
4. **Enterprise Support**: Contact us for enterprise support options

### Reporting Issues

When reporting issues, please include:
- Operating system and version
- Docker and Docker Compose versions
- Application logs
- Steps to reproduce
- Expected vs actual behavior

### Contributing

We welcome contributions! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Erlang/OTP team for the robust platform
- PostgreSQL team for the excellent database
- Redis team for the fast cache
- WebRTC community for real-time communication standards
- All contributors and users of this project

---

**AetherTalk Backend** - Enterprise-ready messaging platform built for scale, security, and performance.

For more information, visit our [website](https://aethertalk.com) or contact us at [support@aethertalk.com](mailto:support@aethertalk.com).