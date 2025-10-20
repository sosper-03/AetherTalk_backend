# AetherTalk Cloud Integration & Testing Guide

## 🎯 Project Overview

This guide provides comprehensive instructions for connecting AetherTalk to cloud databases and performing thorough testing of all application endpoints and functionalities.

## ✅ Completed Tasks

### 1. Cloud Database Configuration
- ✅ **Neon PostgreSQL Setup**: Created configuration for serverless PostgreSQL
- ✅ **Redis Cluster Setup**: Configured Redis for caching and real-time messaging
- ✅ **Environment Configuration**: Created `.env.cloud` with all cloud service settings

### 2. Cloud Media Storage Integration
- ✅ **MEGA Storage**: Implemented MEGA cloud storage integration
- ✅ **Google Drive Support**: Added Google Drive API integration
- ✅ **OneDrive Support**: Added Microsoft OneDrive integration
- ✅ **Unified Storage Manager**: Created cloud storage manager with provider switching

### 3. Application Configuration
- ✅ **Cloud Config**: Created `config/cloud.config` for cloud deployments
- ✅ **Environment Variables**: Comprehensive environment variable setup
- ✅ **Startup Scripts**: Created automated startup and testing scripts

### 4. Dependencies & Compilation
- ✅ **Erlang/OTP 27**: Installed and verified
- ✅ **Rebar3**: Build tool installed and working
- ✅ **Project Compilation**: All modules compile successfully
- ✅ **Dependencies**: All required packages installed

### 5. Testing Infrastructure
- ✅ **Comprehensive Test Suite**: Created `comprehensive_test.sh`
- ✅ **Database Setup Script**: Created `setup_database.sh`
- ✅ **Startup Management**: Created `start_aethertalk.sh`

## 🚀 Quick Start Guide

### Step 1: Set Up Cloud Services

#### Neon PostgreSQL
1. Sign up at [Neon](https://console.neon.tech/)
2. Create a new database
3. Copy connection details to `.env.cloud`:
```bash
AETHERTALK_DB_HOST=ep-example-123456.us-east-1.aws.neon.tech
AETHERTALK_DB_PORT=5432
AETHERTALK_DB_NAME=aethertalk
AETHERTALK_DB_USER=your-neon-username
AETHERTALK_DB_PASS=your-neon-password
AETHERTALK_DB_SSL=true
```

#### Redis Cloud
1. Sign up at [Redis Cloud](https://redis.com/try-free/)
2. Create a Redis database
3. Add connection details to `.env.cloud`:
```bash
AETHERTALK_REDIS_HOST=redis-12345.c1.us-east-1-1.ec2.cloud.redislabs.com
AETHERTALK_REDIS_PORT=12345
AETHERTALK_REDIS_PASSWORD=your-redis-password
AETHERTALK_REDIS_SSL=true
```

#### MEGA Storage
1. Create a MEGA account
2. Add credentials to `.env.cloud`:
```bash
MEGA_USERNAME=your-mega-email@example.com
MEGA_PASSWORD=your-mega-password
```

### Step 2: Configure Environment
```bash
# Copy the cloud environment template
cp .env.cloud .env

# Edit .env with your actual credentials
nano .env
```

### Step 3: Set Up Database
```bash
# Run database setup (requires PostgreSQL connection)
./setup_database.sh
```

### Step 4: Start Application
```bash
# Start in development mode
./start_aethertalk.sh start shell

# Or start as daemon
./start_aethertalk.sh start daemon

# Check status
./start_aethertalk.sh status
```

### Step 5: Run Comprehensive Tests
```bash
# Run all tests
./comprehensive_test.sh

# Or use the startup script
./start_aethertalk.sh test
```

## 📋 Testing Checklist

### Core API Tests
- [ ] Health endpoint (`/health`)
- [ ] Metrics endpoint (`/metrics`)
- [ ] Security headers validation

### Authentication Tests
- [ ] User registration (`POST /api/v1/auth/register`)
- [ ] User login (`POST /api/v1/auth/login`)
- [ ] JWT token validation
- [ ] User profile operations

### Messaging Tests
- [ ] Chat creation (`POST /api/v1/chats`)
- [ ] Message sending (`POST /api/v1/messages`)
- [ ] Message retrieval (`GET /api/v1/messages/:chat_id`)
- [ ] Message editing and deletion

### Media Tests
- [ ] File upload (`POST /api/v1/media/upload`)
- [ ] File download (`GET /api/v1/media/:id`)
- [ ] Cloud storage integration
- [ ] Media processing (thumbnails, compression)

### Real-time Tests
- [ ] WebSocket connection (`ws://localhost:8081/ws`)
- [ ] Real-time messaging
- [ ] Presence indicators
- [ ] Typing indicators

### Call System Tests
- [ ] Voice call initiation (`POST /api/v1/calls`)
- [ ] Video call support
- [ ] WebRTC signaling (`POST /api/v1/calls/:id/signal`)
- [ ] STUN/TURN server integration

### Translation Tests
- [ ] Text translation (`POST /api/v1/translate`)
- [ ] Language detection
- [ ] Real-time translation

### Security Tests
- [ ] Rate limiting
- [ ] JWT authentication
- [ ] Input validation
- [ ] CORS headers

### Performance Tests
- [ ] Load testing
- [ ] Connection limits
- [ ] Database performance
- [ ] Memory usage

## 🛠️ Available Scripts

### `start_aethertalk.sh`
Main application management script:
```bash
./start_aethertalk.sh start [shell|daemon|foreground]  # Start application
./start_aethertalk.sh stop                             # Stop application
./start_aethertalk.sh restart [mode]                   # Restart application
./start_aethertalk.sh status                           # Check status
./start_aethertalk.sh test                             # Run tests
./start_aethertalk.sh setup-db                         # Setup database
```

### `comprehensive_test.sh`
Complete testing suite covering all endpoints and functionalities:
```bash
./comprehensive_test.sh  # Run all tests
```

### `setup_database.sh`
Database initialization and migration:
```bash
./setup_database.sh              # Full setup
./setup_database.sh --verify     # Verify setup only
./setup_database.sh --schema-only # Schema only
```

## 🔧 Configuration Files

### Environment Files
- `.env.example` - Template with all available options
- `.env.cloud` - Cloud-specific configuration template
- `.env` - Your actual configuration (create from template)

### Application Config
- `config/sys.config` - Default application configuration
- `config/cloud.config` - Cloud-optimized configuration
- `config/vm.args` - Erlang VM arguments

## 🌐 Cloud Service Integration

### Supported Storage Providers
1. **MEGA** - Primary choice (50GB free)
2. **Google Drive** - Alternative (15GB free)
3. **Microsoft OneDrive** - Alternative (5GB free)

### Database Services
1. **Neon PostgreSQL** - Serverless PostgreSQL with generous free tier
2. **Redis Cloud** - Managed Redis with free tier

### Translation Services
1. **Google Translate API** - High accuracy, paid service
2. **Azure Translator** - Microsoft's translation service
3. **AWS Translate** - Amazon's translation service
4. **LibreTranslate** - Self-hosted open-source option

## 🚨 Troubleshooting

### Common Issues

#### Database Connection Failed
```
Error: econnrefused
Solution: Verify database credentials and network connectivity
```

#### Redis Connection Failed
```
Error: Redis connection timeout
Solution: Check Redis host, port, and authentication
```

#### Application Won't Start
```
Error: Failed to boot aethertalk
Solution: Check logs in ./logs/ directory for specific errors
```

#### Tests Failing
```
Error: Service not available
Solution: Ensure application is running before running tests
```

### Debug Commands
```bash
# Check application logs
tail -f logs/console.log

# Check error logs
tail -f logs/error.log

# Verify database connection
./setup_database.sh --verify

# Check process status
ps aux | grep beam
```

## 📊 Expected Test Results

When all services are properly configured, you should see:
- ✅ All health checks passing
- ✅ Database connectivity confirmed
- ✅ Redis connectivity confirmed
- ✅ Authentication flow working
- ✅ Message sending/receiving functional
- ✅ Media upload/download working
- ✅ WebSocket connections established
- ✅ Translation services responding

## 🎉 Success Criteria

The setup is complete when:
1. Application starts without errors
2. All API endpoints respond correctly
3. WebSocket connections work
4. Database operations succeed
5. Cloud storage integration functions
6. Real-time features operate properly
7. All tests pass in the comprehensive test suite

## 📞 Support

For issues or questions:
1. Check the logs in `./logs/` directory
2. Verify environment configuration
3. Ensure all cloud services are properly set up
4. Review the troubleshooting section above

---

**AetherTalk** - Enterprise-grade messaging platform with cloud integration ☁️