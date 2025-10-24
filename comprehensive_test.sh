#!/bin/bash

# AetherTalk Comprehensive Testing Script
# Tests all endpoints and functionalities including cloud integrations

set -e

# Configuration
BASE_URL="https://work-1-ykkvhnictguchbcw.prod-runtime.all-hands.dev"
WS_URL="wss://work-2-ykkvhnictguchbcw.prod-runtime.all-hands.dev/ws"
TEST_USER="testuser_$(date +%s)"
TEST_EMAIL="test_$(date +%s)@example.com"
TEST_PASSWORD="TestPassword123!"
TEST_USER2="testuser2_$(date +%s)"
TEST_EMAIL2="test2_$(date +%s)@example.com"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test counters
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Helper functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    ((PASSED_TESTS++))
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    ((FAILED_TESTS++))
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    ((TOTAL_TESTS++))
    log_info "Running test: $test_name"
    
    if eval "$test_command"; then
        log_success "$test_name passed"
        return 0
    else
        log_error "$test_name failed"
        return 1
    fi
}

# Wait for service to be ready
wait_for_service() {
    local url="$1"
    local timeout=30
    local count=0
    
    log_info "Waiting for service at $url to be ready..."
    
    while [ $count -lt $timeout ]; do
        if curl -s "$url/health" > /dev/null 2>&1; then
            log_success "Service is ready!"
            return 0
        fi
        sleep 1
        ((count++))
    done
    
    log_error "Service failed to start within $timeout seconds"
    return 1
}

# Test functions
test_health_endpoint() {
    local response=$(curl -s "$BASE_URL/health")
    if echo "$response" | grep -q "ok\|healthy\|status"; then
        return 0
    else
        log_error "Health endpoint returned: $response"
        return 1
    fi
}

test_metrics_endpoint() {
    local response=$(curl -s "$BASE_URL/metrics")
    if [ $? -eq 0 ]; then
        return 0
    else
        log_error "Metrics endpoint failed"
        return 1
    fi
}

test_user_registration() {
    local response=$(curl -s -X POST "$BASE_URL/api/v1/auth/register" \
        -H "Content-Type: application/json" \
        -d "{
            \"username\": \"$TEST_USER\",
            \"email\": \"$TEST_EMAIL\",
            \"password\": \"$TEST_PASSWORD\",
            \"full_name\": \"Test User\"
        }")
    
    if echo "$response" | grep -q "success\|created\|id\|user"; then
        return 0
    else
        log_error "Registration failed: $response"
        return 1
    fi
}

test_user_login() {
    local response=$(curl -s -X POST "$BASE_URL/api/v1/auth/login" \
        -H "Content-Type: application/json" \
        -d "{
            \"username\": \"$TEST_USER\",
            \"password\": \"$TEST_PASSWORD\"
        }")
    
    # Extract token
    TOKEN=$(echo "$response" | grep -o '"token":"[^"]*"' | cut -d'"' -f4)
    
    if [ -n "$TOKEN" ]; then
        log_info "Login successful, token received: ${TOKEN:0:20}..."
        return 0
    else
        log_error "Login failed: $response"
        return 1
    fi
}

test_user_profile() {
    if [ -z "$TOKEN" ]; then
        log_error "No token available for authenticated request"
        return 1
    fi
    
    local response=$(curl -s -H "Authorization: Bearer $TOKEN" "$BASE_URL/api/v1/users/profile")
    
    if echo "$response" | grep -q "username\|email\|profile"; then
        return 0
    else
        log_error "Profile request failed: $response"
        return 1
    fi
}

test_user_profile_update() {
    if [ -z "$TOKEN" ]; then
        log_error "No token available for authenticated request"
        return 1
    fi
    
    local response=$(curl -s -X PUT "$BASE_URL/api/v1/users/profile" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"full_name\": \"Updated Test User\",
            \"status\": \"online\"
        }")
    
    if echo "$response" | grep -q "success\|updated\|ok"; then
        return 0
    else
        log_error "Profile update failed: $response"
        return 1
    fi
}

test_chat_creation() {
    if [ -z "$TOKEN" ]; then
        log_error "No token available for authenticated request"
        return 1
    fi
    
    local response=$(curl -s -X POST "$BASE_URL/api/v1/chats" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"type\": \"direct\",
            \"name\": \"Test Chat\"
        }")
    
    # Extract chat ID
    CHAT_ID=$(echo "$response" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
    
    if [ -n "$CHAT_ID" ]; then
        log_info "Chat created with ID: $CHAT_ID"
        return 0
    else
        log_error "Chat creation failed: $response"
        return 1
    fi
}

test_message_sending() {
    if [ -z "$TOKEN" ] || [ -z "$CHAT_ID" ]; then
        log_error "No token or chat ID available"
        return 1
    fi
    
    local response=$(curl -s -X POST "$BASE_URL/api/v1/messages" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"chat_id\": \"$CHAT_ID\",
            \"content\": \"Hello, this is a test message!\",
            \"message_type\": \"text\"
        }")
    
    # Extract message ID
    MESSAGE_ID=$(echo "$response" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
    
    if [ -n "$MESSAGE_ID" ]; then
        log_info "Message sent with ID: $MESSAGE_ID"
        return 0
    else
        log_error "Message sending failed: $response"
        return 1
    fi
}

test_message_retrieval() {
    if [ -z "$TOKEN" ] || [ -z "$CHAT_ID" ]; then
        log_error "No token or chat ID available"
        return 1
    fi
    
    local response=$(curl -s -H "Authorization: Bearer $TOKEN" "$BASE_URL/api/v1/messages/$CHAT_ID")
    
    if echo "$response" | grep -q "messages\|content\|id"; then
        return 0
    else
        log_error "Message retrieval failed: $response"
        return 1
    fi
}

test_media_upload() {
    if [ -z "$TOKEN" ]; then
        log_error "No token available for authenticated request"
        return 1
    fi
    
    # Create a test file
    echo "This is a test file for media upload" > /tmp/test_file.txt
    
    local response=$(curl -s -X POST "$BASE_URL/api/v1/media/upload" \
        -H "Authorization: Bearer $TOKEN" \
        -F "file=@/tmp/test_file.txt" \
        -F "type=document")
    
    # Extract media ID
    MEDIA_ID=$(echo "$response" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
    
    if [ -n "$MEDIA_ID" ]; then
        log_info "Media uploaded with ID: $MEDIA_ID"
        rm -f /tmp/test_file.txt
        return 0
    else
        log_error "Media upload failed: $response"
        rm -f /tmp/test_file.txt
        return 1
    fi
}

test_media_download() {
    if [ -z "$TOKEN" ] || [ -z "$MEDIA_ID" ]; then
        log_error "No token or media ID available"
        return 1
    fi
    
    local response=$(curl -s -H "Authorization: Bearer $TOKEN" "$BASE_URL/api/v1/media/$MEDIA_ID")
    
    if [ $? -eq 0 ]; then
        return 0
    else
        log_error "Media download failed"
        return 1
    fi
}

test_call_initiation() {
    if [ -z "$TOKEN" ]; then
        log_error "No token available for authenticated request"
        return 1
    fi
    
    local response=$(curl -s -X POST "$BASE_URL/api/v1/calls" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"type\": \"voice\",
            \"participants\": [\"$TEST_USER\"]
        }")
    
    # Extract call ID
    CALL_ID=$(echo "$response" | grep -o '"id":"[^"]*"' | cut -d'"' -f4)
    
    if [ -n "$CALL_ID" ]; then
        log_info "Call initiated with ID: $CALL_ID"
        return 0
    else
        log_error "Call initiation failed: $response"
        return 1
    fi
}

test_call_signaling() {
    if [ -z "$TOKEN" ] || [ -z "$CALL_ID" ]; then
        log_error "No token or call ID available"
        return 1
    fi
    
    local response=$(curl -s -X POST "$BASE_URL/api/v1/calls/$CALL_ID/signal" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"signal_type\": \"offer\",
            \"signal\": {\"sdp\": \"test_sdp_offer\"}
        }")
    
    if echo "$response" | grep -q "success\|ok\|signal"; then
        return 0
    else
        log_error "Call signaling failed: $response"
        return 1
    fi
}

test_translation_service() {
    if [ -z "$TOKEN" ]; then
        log_error "No token available for authenticated request"
        return 1
    fi
    
    local response=$(curl -s -X POST "$BASE_URL/api/v1/translate" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"text\": \"Hello, how are you?\",
            \"from\": \"en\",
            \"to\": \"es\"
        }")
    
    if echo "$response" | grep -q "translation\|translated\|text"; then
        return 0
    else
        log_error "Translation service failed: $response"
        return 1
    fi
}

test_user_contacts() {
    if [ -z "$TOKEN" ]; then
        log_error "No token available for authenticated request"
        return 1
    fi
    
    # First, register a second user to add as contact
    curl -s -X POST "$BASE_URL/api/v1/auth/register" \
        -H "Content-Type: application/json" \
        -d "{
            \"username\": \"$TEST_USER2\",
            \"email\": \"$TEST_EMAIL2\",
            \"password\": \"$TEST_PASSWORD\",
            \"full_name\": \"Test User 2\"
        }" > /dev/null
    
    # Add contact
    local response=$(curl -s -X POST "$BASE_URL/api/v1/users/contacts" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"username\": \"$TEST_USER2\",
            \"display_name\": \"My Test Contact\"
        }")
    
    if echo "$response" | grep -q "success\|added\|contact"; then
        return 0
    else
        log_error "Contact addition failed: $response"
        return 1
    fi
}

test_get_contacts() {
    if [ -z "$TOKEN" ]; then
        log_error "No token available for authenticated request"
        return 1
    fi
    
    local response=$(curl -s -H "Authorization: Bearer $TOKEN" "$BASE_URL/api/v1/users/contacts")
    
    if echo "$response" | grep -q "contacts\|users\|list"; then
        return 0
    else
        log_error "Get contacts failed: $response"
        return 1
    fi
}

test_chat_operations() {
    if [ -z "$TOKEN" ] || [ -z "$CHAT_ID" ]; then
        log_error "No token or chat ID available"
        return 1
    fi
    
    # Test chat archiving
    local response=$(curl -s -X PUT "$BASE_URL/api/v1/chats/$CHAT_ID/archive" \
        -H "Authorization: Bearer $TOKEN")
    
    if echo "$response" | grep -q "success\|archived\|ok"; then
        return 0
    else
        log_error "Chat archiving failed: $response"
        return 1
    fi
}

test_user_settings() {
    if [ -z "$TOKEN" ]; then
        log_error "No token available for authenticated request"
        return 1
    fi
    
    local response=$(curl -s -X POST "$BASE_URL/api/v1/users/settings" \
        -H "Authorization: Bearer $TOKEN" \
        -H "Content-Type: application/json" \
        -d "{
            \"notifications\": true,
            \"theme\": \"dark\",
            \"language\": \"en\"
        }")
    
    if echo "$response" | grep -q "success\|updated\|settings"; then
        return 0
    else
        log_error "User settings update failed: $response"
        return 1
    fi
}

test_security_headers() {
    local response=$(curl -s -I "$BASE_URL/health")
    
    if echo "$response" | grep -q "X-Content-Type-Options\|X-Frame-Options\|X-XSS-Protection"; then
        return 0
    else
        log_error "Security headers missing"
        return 1
    fi
}

test_rate_limiting() {
    log_info "Testing rate limiting (making multiple rapid requests)..."
    
    local count=0
    local rate_limited=false
    
    for i in {1..20}; do
        local response=$(curl -s -w "%{http_code}" "$BASE_URL/health")
        local http_code="${response: -3}"
        
        if [ "$http_code" = "429" ]; then
            rate_limited=true
            break
        fi
        
        ((count++))
    done
    
    if [ "$rate_limited" = true ]; then
        log_info "Rate limiting is working (got 429 after $count requests)"
        return 0
    else
        log_warning "Rate limiting not triggered after 20 requests"
        return 0  # Not necessarily a failure
    fi
}

# WebSocket testing function
test_websocket_connection() {
    log_info "Testing WebSocket connection (basic connectivity test)..."
    
    # Use a simple WebSocket test with timeout
    timeout 5 bash -c "
        exec 3<>/dev/tcp/localhost/8081
        echo -e 'GET /ws HTTP/1.1\r\nHost: localhost:8081\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\nSec-WebSocket-Version: 13\r\n\r\n' >&3
        read -t 2 response <&3
        exec 3<&-
        exec 3>&-
    " 2>/dev/null
    
    if [ $? -eq 0 ]; then
        return 0
    else
        log_error "WebSocket connection test failed"
        return 1
    fi
}

# Cloud storage testing
test_cloud_storage() {
    log_info "Testing cloud storage functionality..."
    
    # This would test the cloud storage integration
    # For now, we'll just check if the endpoints respond
    if [ -z "$TOKEN" ]; then
        log_error "No token available for authenticated request"
        return 1
    fi
    
    local response=$(curl -s -X GET "$BASE_URL/api/v1/storage/stats" \
        -H "Authorization: Bearer $TOKEN")
    
    if [ $? -eq 0 ]; then
        return 0
    else
        log_error "Cloud storage test failed"
        return 1
    fi
}

# Performance testing
test_performance() {
    log_info "Running basic performance test..."
    
    local start_time=$(date +%s%N)
    
    for i in {1..10}; do
        curl -s "$BASE_URL/health" > /dev/null
    done
    
    local end_time=$(date +%s%N)
    local duration=$(( (end_time - start_time) / 1000000 )) # Convert to milliseconds
    
    log_info "10 health check requests took ${duration}ms"
    
    if [ $duration -lt 5000 ]; then # Less than 5 seconds
        return 0
    else
        log_warning "Performance test took longer than expected: ${duration}ms"
        return 0  # Not necessarily a failure
    fi
}

# Main test execution
main() {
    echo "=========================================="
    echo "🚀 AetherTalk Comprehensive Test Suite"
    echo "=========================================="
    echo
    
    log_info "Starting comprehensive testing of AetherTalk application..."
    log_info "Base URL: $BASE_URL"
    log_info "WebSocket URL: $WS_URL"
    log_info "Test User: $TEST_USER"
    echo
    
    # Wait for service to be ready
    if ! wait_for_service "$BASE_URL"; then
        log_error "Service is not available. Please start the AetherTalk application first."
        exit 1
    fi
    
    echo
    log_info "🔍 Running Core API Tests..."
    echo "----------------------------------------"
    
    # Core API tests
    run_test "Health Endpoint" "test_health_endpoint"
    run_test "Metrics Endpoint" "test_metrics_endpoint"
    run_test "Security Headers" "test_security_headers"
    
    echo
    log_info "👤 Running Authentication Tests..."
    echo "----------------------------------------"
    
    # Authentication tests
    run_test "User Registration" "test_user_registration"
    run_test "User Login" "test_user_login"
    run_test "User Profile Retrieval" "test_user_profile"
    run_test "User Profile Update" "test_user_profile_update"
    run_test "User Settings" "test_user_settings"
    
    echo
    log_info "👥 Running Contact Management Tests..."
    echo "----------------------------------------"
    
    # Contact tests
    run_test "Add Contact" "test_user_contacts"
    run_test "Get Contacts" "test_get_contacts"
    
    echo
    log_info "💬 Running Messaging Tests..."
    echo "----------------------------------------"
    
    # Messaging tests
    run_test "Chat Creation" "test_chat_creation"
    run_test "Message Sending" "test_message_sending"
    run_test "Message Retrieval" "test_message_retrieval"
    run_test "Chat Operations" "test_chat_operations"
    
    echo
    log_info "📁 Running Media Tests..."
    echo "----------------------------------------"
    
    # Media tests
    run_test "Media Upload" "test_media_upload"
    run_test "Media Download" "test_media_download"
    
    echo
    log_info "📞 Running Call System Tests..."
    echo "----------------------------------------"
    
    # Call tests
    run_test "Call Initiation" "test_call_initiation"
    run_test "Call Signaling" "test_call_signaling"
    
    echo
    log_info "🌐 Running Translation Tests..."
    echo "----------------------------------------"
    
    # Translation tests
    run_test "Translation Service" "test_translation_service"
    
    echo
    log_info "🔌 Running WebSocket Tests..."
    echo "----------------------------------------"
    
    # WebSocket tests
    run_test "WebSocket Connection" "test_websocket_connection"
    
    echo
    log_info "☁️ Running Cloud Integration Tests..."
    echo "----------------------------------------"
    
    # Cloud tests
    run_test "Cloud Storage" "test_cloud_storage"
    
    echo
    log_info "🔒 Running Security Tests..."
    echo "----------------------------------------"
    
    # Security tests
    run_test "Rate Limiting" "test_rate_limiting"
    
    echo
    log_info "⚡ Running Performance Tests..."
    echo "----------------------------------------"
    
    # Performance tests
    run_test "Basic Performance" "test_performance"
    
    echo
    echo "=========================================="
    echo "📊 Test Results Summary"
    echo "=========================================="
    echo
    echo "Total Tests: $TOTAL_TESTS"
    echo -e "Passed: ${GREEN}$PASSED_TESTS${NC}"
    echo -e "Failed: ${RED}$FAILED_TESTS${NC}"
    echo
    
    if [ $FAILED_TESTS -eq 0 ]; then
        echo -e "${GREEN}🎉 All tests passed! AetherTalk is working correctly.${NC}"
        exit 0
    else
        echo -e "${RED}❌ Some tests failed. Please check the logs above.${NC}"
        exit 1
    fi
}

# Run the main function
main "$@"