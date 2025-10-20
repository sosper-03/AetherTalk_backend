# AetherTalk Phone Features Guide

## 📱 WhatsApp-like Phone Integration

AetherTalk now includes comprehensive phone number verification and calling features, similar to WhatsApp's functionality.

## 🎯 Key Features Implemented

### 1. Phone Number Registration & Verification
- **WhatsApp-style signup**: Users register with their phone number
- **SMS verification**: 6-digit verification codes sent via Firebase/SMS service
- **One-time verification**: Once verified, no re-verification needed (like WhatsApp)
- **Automatic verification**: Phone numbers are automatically verified on first successful code entry

### 2. Phone-to-Phone Calling
- **Direct calling**: Users can call each other using registered phone numbers
- **Voice & Video**: Support for both voice and video calls
- **Call discovery**: Find users by their phone number
- **Call history**: Complete call logs with duration and status
- **Real-time notifications**: Push notifications for incoming calls

### 3. Cloud Integration
- **Neon PostgreSQL**: Serverless database for user data and call logs
- **Redis Cloud**: Real-time caching and session management
- **MEGA Storage**: 50GB free cloud storage for media files
- **Firebase Auth**: Phone number verification service

## 🚀 API Endpoints

### Phone Verification Endpoints

#### Send Verification Code
```http
POST /api/v1/phone/send-verification
Content-Type: application/json

{
  "phone_number": "+1234567890"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Verification code sent",
  "message_id": "firebase_message_id"
}
```

#### Verify Code
```http
POST /api/v1/phone/verify-code
Content-Type: application/json

{
  "phone_number": "+1234567890",
  "code": "123456"
}
```

**Response:**
```json
{
  "success": true,
  "message": "Phone number verified successfully",
  "verified": true
}
```

#### Resend Code
```http
POST /api/v1/phone/resend-code
Content-Type: application/json

{
  "phone_number": "+1234567890"
}
```

#### Check Verification Status
```http
GET /api/v1/phone/verification-status?phone_number=+1234567890
```

**Response:**
```json
{
  "phone_number": "+1234567890",
  "status": "verified",
  "verified_at": "2025-10-20T13:45:00Z"
}
```

### Phone Calling Endpoints

#### Initiate Call
```http
POST /api/v1/phone/call
Authorization: Bearer <jwt_token>
Content-Type: application/json

{
  "phone_number": "+0987654321",
  "call_type": "voice"
}
```

**Response:**
```json
{
  "success": true,
  "call_id": "call_uuid",
  "status": "ringing"
}
```

#### Answer Call
```http
POST /api/v1/phone/call/{call_id}/answer
Authorization: Bearer <jwt_token>
```

#### Reject Call
```http
POST /api/v1/phone/call/{call_id}/reject
Authorization: Bearer <jwt_token>
```

#### End Call
```http
POST /api/v1/phone/call/{call_id}/end
Authorization: Bearer <jwt_token>
```

#### Get Active Calls
```http
GET /api/v1/phone/calls/active
Authorization: Bearer <jwt_token>
```

#### Get Call History
```http
GET /api/v1/phone/calls/history?limit=50
Authorization: Bearer <jwt_token>
```

**Response:**
```json
{
  "success": true,
  "call_history": [
    {
      "call_id": "call_uuid",
      "caller_phone": "+1234567890",
      "callee_phone": "+0987654321",
      "call_type": "voice",
      "status": "ended",
      "started_at": "2025-10-20T13:45:00Z",
      "answered_at": "2025-10-20T13:45:05Z",
      "ended_at": "2025-10-20T13:47:30Z",
      "duration": 145
    }
  ]
}
```

#### Find User by Phone
```http
GET /api/v1/phone/find-user?phone_number=+1234567890
Authorization: Bearer <jwt_token>
```

## 🔧 Configuration

### Environment Variables

```bash
# Firebase Configuration (Phone Authentication)
FIREBASE_PROJECT_ID=your-firebase-project-id
FIREBASE_WEB_API_KEY=your-web-api-key
FIREBASE_PRIVATE_KEY=your-private-key
FIREBASE_CLIENT_EMAIL=your-service-account-email

# Phone Verification Settings
PHONE_VERIFICATION_ENABLED=true
PHONE_VERIFICATION_TIMEOUT=300
PHONE_VERIFICATION_MAX_ATTEMPTS=3
PHONE_VERIFICATION_RESEND_DELAY=60

# Cloud Database (Neon PostgreSQL)
AETHERTALK_DB_HOST=ep-plain-heart-adeyfder-pooler.c-2.us-east-1.aws.neon.tech
AETHERTALK_DB_PORT=5432
AETHERTALK_DB_NAME=neondb
AETHERTALK_DB_USER=neondb_owner
AETHERTALK_DB_PASS=npg_lvHjeID2YsT6

# Redis Cloud
AETHERTALK_REDIS_HOST=redis-13729.c341.af-south-1-1.ec2.redns.redis-cloud.com
AETHERTALK_REDIS_PORT=13729
AETHERTALK_REDIS_PASSWORD=E3ynQ1MjRf1lrKkkLqgzvKbzlEwkkjmo

# MEGA Storage
MEGA_USERNAME=adolphchenge@gmail.com
MEGA_PASSWORD=Adolph2002#
```

## 📊 Database Schema

### Users Table (Updated)
```sql
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE NOT NULL,
    phone_number VARCHAR(20) UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    full_name VARCHAR(255),
    avatar_url TEXT,
    status VARCHAR(20) DEFAULT 'offline',
    last_seen TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    is_verified BOOLEAN DEFAULT FALSE,
    phone_verified BOOLEAN DEFAULT FALSE,
    is_active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

### Phone Verifications Table
```sql
CREATE TABLE phone_verifications (
    phone_number VARCHAR(20) PRIMARY KEY,
    verified BOOLEAN DEFAULT FALSE,
    verified_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

### Phone Calls Table
```sql
CREATE TABLE phone_calls (
    call_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    caller_phone VARCHAR(20) NOT NULL,
    callee_phone VARCHAR(20) NOT NULL,
    caller_user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    callee_user_id UUID REFERENCES users(id) ON DELETE CASCADE,
    call_type VARCHAR(10) NOT NULL CHECK (call_type IN ('voice', 'video')),
    status VARCHAR(20) NOT NULL CHECK (status IN ('ringing', 'active', 'ended', 'rejected')),
    started_at TIMESTAMP WITH TIME ZONE NOT NULL,
    answered_at TIMESTAMP WITH TIME ZONE,
    ended_at TIMESTAMP WITH TIME ZONE,
    duration INTEGER, -- Duration in seconds
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

## 🔄 User Registration Flow (WhatsApp-style)

### 1. Initial Registration
```javascript
// User enters phone number
const response = await fetch('/api/v1/phone/send-verification', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    phone_number: '+1234567890'
  })
});
```

### 2. Code Verification
```javascript
// User enters 6-digit code
const response = await fetch('/api/v1/phone/verify-code', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    phone_number: '+1234567890',
    code: '123456'
  })
});
```

### 3. Complete Registration
```javascript
// After phone verification, complete user registration
const response = await fetch('/api/v1/auth/register', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({
    phone_number: '+1234567890',
    username: 'john_doe',
    full_name: 'John Doe',
    password: 'secure_password'
  })
});
```

## 📞 Calling Flow

### 1. Initiate Call
```javascript
const response = await fetch('/api/v1/phone/call', {
  method: 'POST',
  headers: {
    'Authorization': 'Bearer ' + jwt_token,
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({
    phone_number: '+0987654321',
    call_type: 'voice'
  })
});
```

### 2. Handle Incoming Call (WebSocket)
```javascript
websocket.onmessage = function(event) {
  const data = JSON.parse(event.data);
  
  if (data.type === 'incoming_call') {
    // Show incoming call UI
    showIncomingCallUI(data.data);
  }
};
```

### 3. Answer/Reject Call
```javascript
// Answer call
await fetch(`/api/v1/phone/call/${call_id}/answer`, {
  method: 'POST',
  headers: { 'Authorization': 'Bearer ' + jwt_token }
});

// Reject call
await fetch(`/api/v1/phone/call/${call_id}/reject`, {
  method: 'POST',
  headers: { 'Authorization': 'Bearer ' + jwt_token }
});
```

## 🔐 Security Features

### Phone Number Verification
- **Rate limiting**: Prevents spam verification requests
- **Attempt limits**: Maximum 3 verification attempts per code
- **Time limits**: Verification codes expire after 5 minutes
- **Resend delays**: 60-second delay between resend requests

### Call Security
- **Authentication required**: All call endpoints require JWT tokens
- **Authorization checks**: Users can only answer/reject their own calls
- **Call validation**: Prevents calling yourself or invalid numbers

## 🌐 Real-time Features

### WebSocket Events
- `incoming_call`: Notification of incoming call
- `call_answered`: Call was answered by recipient
- `call_rejected`: Call was rejected by recipient
- `call_ended`: Call was ended by either party

### Push Notifications
- Incoming call notifications
- Call status updates
- Verification code delivery (SMS)

## 🧪 Testing

### Run Cloud Services Test
```bash
./test_cloud_services.sh
```

### Run Comprehensive API Tests
```bash
./comprehensive_test.sh
```

### Manual Testing Examples

#### Test Phone Verification
```bash
# Send verification code
curl -X POST http://localhost:8080/api/v1/phone/send-verification \
  -H "Content-Type: application/json" \
  -d '{"phone_number": "+1234567890"}'

# Verify code
curl -X POST http://localhost:8080/api/v1/phone/verify-code \
  -H "Content-Type: application/json" \
  -d '{"phone_number": "+1234567890", "code": "123456"}'
```

#### Test Phone Calling
```bash
# Initiate call
curl -X POST http://localhost:8080/api/v1/phone/call \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"phone_number": "+0987654321", "call_type": "voice"}'
```

## 🚀 Deployment

### 1. Set up Cloud Services
- Create Neon PostgreSQL database
- Set up Redis Cloud instance
- Configure MEGA storage account
- Set up Firebase project for SMS

### 2. Configure Environment
```bash
cp .env.cloud .env
# Edit .env with your actual credentials
```

### 3. Initialize Database
```bash
./setup_database.sh
```

### 4. Start Application
```bash
./start_aethertalk.sh start daemon
```

### 5. Test Everything
```bash
./test_cloud_services.sh
./comprehensive_test.sh
```

## 📱 Mobile App Integration

### iOS/Android Implementation
```javascript
// React Native example
import { requestPhoneVerification, verifyPhoneCode } from './api';

const handlePhoneVerification = async (phoneNumber) => {
  try {
    await requestPhoneVerification(phoneNumber);
    // Show code input UI
  } catch (error) {
    console.error('Verification failed:', error);
  }
};

const handleCodeVerification = async (phoneNumber, code) => {
  try {
    const result = await verifyPhoneCode(phoneNumber, code);
    if (result.verified) {
      // Proceed to main app
      navigateToMainApp();
    }
  } catch (error) {
    console.error('Code verification failed:', error);
  }
};
```

## 🎉 Success Metrics

✅ **Phone Verification**: WhatsApp-style SMS verification implemented  
✅ **Phone Calling**: Direct phone-to-phone calling functionality  
✅ **Cloud Integration**: Neon PostgreSQL, Redis Cloud, MEGA storage  
✅ **Real-time Features**: WebSocket notifications and call signaling  
✅ **Security**: Rate limiting, authentication, and authorization  
✅ **API Coverage**: Complete REST API for all phone features  
✅ **Database Schema**: Optimized tables for phone features  
✅ **Testing**: Comprehensive test suite for all functionality  

## 📞 Support

For questions or issues:
1. Check the logs in `./logs/` directory
2. Run `./test_cloud_services.sh` to verify connectivity
3. Review the API documentation above
4. Check environment variable configuration

---

**AetherTalk** - Now with WhatsApp-like phone integration! 📱✨