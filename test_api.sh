#!/bin/bash

# AetherTalk API Test Script

set -e

BASE_URL="http://localhost:8080"
WS_URL="ws://localhost:8081/ws"

echo "🧪 Testing AetherTalk API"
echo "========================"

# Test health endpoint
echo "1. Testing health endpoint..."
curl -s "$BASE_URL/health" | jq '.' || echo "Health check failed"

# Test metrics endpoint
echo -e "\n2. Testing metrics endpoint..."
curl -s "$BASE_URL/metrics" | jq '.' || echo "Metrics check failed"

# Test user registration
echo -e "\n3. Testing user registration..."
REGISTER_RESPONSE=$(curl -s -X POST "$BASE_URL/api/v1/auth/register" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "email": "test@example.com",
    "password": "testpassword123",
    "full_name": "Test User"
  }')

echo "Registration response: $REGISTER_RESPONSE"

# Test user login
echo -e "\n4. Testing user login..."
LOGIN_RESPONSE=$(curl -s -X POST "$BASE_URL/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "password": "testpassword123"
  }')

echo "Login response: $LOGIN_RESPONSE"

# Extract token if login was successful
TOKEN=$(echo "$LOGIN_RESPONSE" | jq -r '.token // empty')

if [ -n "$TOKEN" ]; then
    echo "✅ Login successful, token received"
    
    # Test authenticated endpoints
    echo -e "\n5. Testing user profile..."
    curl -s -H "Authorization: Bearer $TOKEN" "$BASE_URL/api/v1/users/profile" | jq '.'
    
    echo -e "\n6. Testing user chats..."
    curl -s -H "Authorization: Bearer $TOKEN" "$BASE_URL/api/v1/chats" | jq '.'
    
else
    echo "❌ Login failed, cannot test authenticated endpoints"
fi

echo -e "\n✅ API tests completed!"
echo "For WebSocket testing, use a WebSocket client to connect to: $WS_URL"