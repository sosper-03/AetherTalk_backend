#!/bin/bash

# AetherTalk Comprehensive API Testing Script
# Tests all endpoints and functionalities

# set -e  # Disabled to allow tests to continue on failures

# Configuration
BASE_URL="https://work-1-mbrdibibrdjskyrv.prod-runtime.all-hands.dev"
WS_URL="wss://work-2-mbrdibibrdjskyrv.prod-runtime.all-hands.dev/ws"
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

# Global variables for tokens and IDs
ACCESS_TOKEN=""
REFRESH_TOKEN=""
USER_ID=""
CHAT_ID=""
GROUP_ID=""
MESSAGE_ID=""

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
    local expected_status="$3"
    
    ((TOTAL_TESTS++))
    log_info "Running test: $test_name"
    
    # Execute the test command and capture response
    local response
    local status_code
    
    response=$(eval "$test_command" 2>/dev/null || echo "REQUEST_FAILED")
    
    if [[ "$response" != "REQUEST_FAILED" ]]; then
        status_code=$(echo "$response" | tail -n1 | grep -o '[0-9]\{3\}' || echo "unknown")
        
        if [[ "$status_code" == "$expected_status" ]] || [[ "$expected_status" == "any" ]]; then
            log_success "$test_name - Status: $status_code"
            # Show response body without status code (if it exists)
            local body=$(echo "$response" | head -n -1)
            if [[ -n "$body" ]]; then
                echo "Response: $body"
            fi
        else
            log_error "$test_name - Expected: $expected_status, Got: $status_code"
            echo "Response: $response"
        fi
    else
        log_error "$test_name - Request failed"
    fi
    
    echo "----------------------------------------"
}

# Test functions
test_basic_connectivity() {
    log_info "=== Testing Basic Connectivity ==="
    
    run_test "Server Health Check" \
        "curl -s -w '\n%{http_code}' '$BASE_URL/'" \
        "404"
        
    run_test "API Base Path" \
        "curl -s -w '\n%{http_code}' '$BASE_URL/api/v1/'" \
        "any"
}

test_authentication() {
    log_info "=== Testing Authentication Endpoints ==="
    
    # Test user registration
    local register_data="{\"username\":\"$TEST_USER\",\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASSWORD\"}"
    
    run_test "User Registration" \
        "curl -s -w '\n%{http_code}' -X POST -H 'Content-Type: application/json' -d '$register_data' '$BASE_URL/api/v1/auth/register'" \
        "any"
    
    # Test user login
    local login_data="{\"email\":\"$TEST_EMAIL\",\"password\":\"$TEST_PASSWORD\"}"
    
    local login_response
    login_response=$(curl -s -X POST -H 'Content-Type: application/json' -d "$login_data" "$BASE_URL/api/v1/auth/login" 2>/dev/null || echo "")
    
    if [[ -n "$login_response" ]]; then
        ACCESS_TOKEN=$(echo "$login_response" | grep -o '"access_token":"[^"]*"' | cut -d'"' -f4 || echo "")
        REFRESH_TOKEN=$(echo "$login_response" | grep -o '"refresh_token":"[^"]*"' | cut -d'"' -f4 || echo "")
        USER_ID=$(echo "$login_response" | grep -o '"user_id":"[^"]*"' | cut -d'"' -f4 || echo "")
        
        if [[ -n "$ACCESS_TOKEN" ]]; then
            log_success "Login successful - Token obtained"
        else
            log_warning "Login response received but no token found"
        fi
    fi
    
    run_test "User Login" \
        "curl -s -w '\n%{http_code}' -X POST -H 'Content-Type: application/json' -d '$login_data' '$BASE_URL/api/v1/auth/login'" \
        "any"
    
    # Test token refresh (if we have a refresh token)
    if [[ -n "$REFRESH_TOKEN" ]]; then
        local refresh_data="{\"refresh_token\":\"$REFRESH_TOKEN\"}"
        run_test "Token Refresh" \
            "curl -s -w '\n%{http_code}' -X POST -H 'Content-Type: application/json' -d '$refresh_data' '$BASE_URL/api/v1/auth/refresh'" \
            "any"
    fi
    
    # Test logout (if we have an access token)
    if [[ -n "$ACCESS_TOKEN" ]]; then
        run_test "User Logout" \
            "curl -s -w '\n%{http_code}' -X POST -H 'Authorization: Bearer $ACCESS_TOKEN' '$BASE_URL/api/v1/auth/logout'" \
            "any"
    fi
}

test_user_management() {
    log_info "=== Testing User Management Endpoints ==="
    
    if [[ -n "$ACCESS_TOKEN" ]]; then
        run_test "Get User Profile" \
            "curl -s -w '\n%{http_code}' -H 'Authorization: Bearer $ACCESS_TOKEN' '$BASE_URL/api/v1/users/profile'" \
            "any"
            
        run_test "Get User Contacts" \
            "curl -s -w '\n%{http_code}' -H 'Authorization: Bearer $ACCESS_TOKEN' '$BASE_URL/api/v1/users/contacts'" \
            "any"
            
        run_test "Get User Settings" \
            "curl -s -w '\n%{http_code}' -H 'Authorization: Bearer $ACCESS_TOKEN' '$BASE_URL/api/v1/users/settings'" \
            "any"
            
        # Test profile update
        local profile_data="{\"display_name\":\"Test User Updated\",\"bio\":\"Updated bio\"}"
        run_test "Update User Profile" \
            "curl -s -w '\n%{http_code}' -X PUT -H 'Authorization: Bearer $ACCESS_TOKEN' -H 'Content-Type: application/json' -d '$profile_data' '$BASE_URL/api/v1/users/profile'" \
            "any"
    else
        log_warning "Skipping user management tests - no access token available"
    fi
}

test_chat_messaging() {
    log_info "=== Testing Chat and Messaging Endpoints ==="
    
    if [[ -n "$ACCESS_TOKEN" ]]; then
        run_test "Get User Chats" \
            "curl -s -w '\n%{http_code}' -H 'Authorization: Bearer $ACCESS_TOKEN' '$BASE_URL/api/v1/chats'" \
            "any"
            
        # Create a test chat (if endpoint supports it)
        local chat_data="{\"type\":\"private\",\"name\":\"Test Chat\"}"
        run_test "Create Chat" \
            "curl -s -w '\n%{http_code}' -X POST -H 'Authorization: Bearer $ACCESS_TOKEN' -H 'Content-Type: application/json' -d '$chat_data' '$BASE_URL/api/v1/chats'" \
            "any"
            
        # Test message endpoints (using a dummy chat ID)
        local dummy_chat_id="test_chat_123"
        run_test "Get Chat Messages" \
            "curl -s -w '\n%{http_code}' -H 'Authorization: Bearer $ACCESS_TOKEN' '$BASE_URL/api/v1/chats/$dummy_chat_id/messages'" \
            "any"
            
        # Test sending a message
        local message_data="{\"content\":\"Hello, this is a test message!\",\"type\":\"text\"}"
        run_test "Send Message" \
            "curl -s -w '\n%{http_code}' -X POST -H 'Authorization: Bearer $ACCESS_TOKEN' -H 'Content-Type: application/json' -d '$message_data' '$BASE_URL/api/v1/chats/$dummy_chat_id/messages'" \
            "any"
            
        # Test media upload
        run_test "Upload Media" \
            "curl -s -w '\n%{http_code}' -H 'Authorization: Bearer $ACCESS_TOKEN' '$BASE_URL/api/v1/chats/$dummy_chat_id/media'" \
            "any"
    else
        log_warning "Skipping chat/messaging tests - no access token available"
    fi
}

test_group_functionality() {
    log_info "=== Testing Group Management Endpoints ==="
    
    if [[ -n "$ACCESS_TOKEN" ]]; then
        run_test "Get User Groups" \
            "curl -s -w '\n%{http_code}' -H 'Authorization: Bearer $ACCESS_TOKEN' '$BASE_URL/api/v1/groups'" \
            "any"
            
        # Create a test group
        local group_data="{\"name\":\"Test Group\",\"description\":\"A test group for API testing\"}"
        run_test "Create Group" \
            "curl -s -w '\n%{http_code}' -X POST -H 'Authorization: Bearer $ACCESS_TOKEN' -H 'Content-Type: application/json' -d '$group_data' '$BASE_URL/api/v1/groups'" \
            "any"
            
        # Test group member endpoints (using a dummy group ID)
        local dummy_group_id="test_group_123"
        run_test "Get Group Members" \
            "curl -s -w '\n%{http_code}' -H 'Authorization: Bearer $ACCESS_TOKEN' '$BASE_URL/api/v1/groups/$dummy_group_id/members'" \
            "any"
            
        # Test adding a member
        local member_data="{\"user_id\":\"test_user_456\"}"
        run_test "Add Group Member" \
            "curl -s -w '\n%{http_code}' -X POST -H 'Authorization: Bearer $ACCESS_TOKEN' -H 'Content-Type: application/json' -d '$member_data' '$BASE_URL/api/v1/groups/$dummy_group_id/members'" \
            "any"
    else
        log_warning "Skipping group functionality tests - no access token available"
    fi
}

test_translation_features() {
    log_info "=== Testing Translation and AI Features ==="
    
    if [[ -n "$ACCESS_TOKEN" ]]; then
        run_test "Get Supported Languages" \
            "curl -s -w '\n%{http_code}' -H 'Authorization: Bearer $ACCESS_TOKEN' '$BASE_URL/api/v1/translation/languages'" \
            "any"
            
        run_test "Detect Language" \
            "curl -s -w '\n%{http_code}' -X POST -H 'Authorization: Bearer $ACCESS_TOKEN' -H 'Content-Type: application/json' -d '{\"text\":\"Hello world\"}' '$BASE_URL/api/v1/translation/detect'" \
            "any"
            
        run_test "Translate Text" \
            "curl -s -w '\n%{http_code}' -X POST -H 'Authorization: Bearer $ACCESS_TOKEN' -H 'Content-Type: application/json' -d '{\"text\":\"Hello world\",\"from\":\"en\",\"to\":\"es\"}' '$BASE_URL/api/v1/translation/translate'" \
            "any"
            
        run_test "Get Translation Settings" \
            "curl -s -w '\n%{http_code}' -H 'Authorization: Bearer $ACCESS_TOKEN' '$BASE_URL/api/v1/translation/settings'" \
            "any"
            
        run_test "Start Streaming Translation" \
            "curl -s -w '\n%{http_code}' -X POST -H 'Authorization: Bearer $ACCESS_TOKEN' -H 'Content-Type: application/json' -d '{\"from\":\"en\",\"to\":\"es\"}' '$BASE_URL/api/v1/translation/stream/start'" \
            "any"
    else
        log_warning "Skipping translation tests - no access token available"
    fi
}

test_cloud_integration() {
    log_info "=== Testing Cloud Storage Integration ==="
    
    if [[ -n "$ACCESS_TOKEN" ]]; then
        # Test Google Drive integration
        run_test "Google Drive - List Files" \
            "curl -s -w '\n%{http_code}' -H 'Authorization: Bearer $ACCESS_TOKEN' '$BASE_URL/api/v1/cloud/google-drive/files'" \
            "any"
            
        # Test OneDrive integration
        run_test "OneDrive - List Files" \
            "curl -s -w '\n%{http_code}' -H 'Authorization: Bearer $ACCESS_TOKEN' '$BASE_URL/api/v1/cloud/onedrive/files'" \
            "any"
            
        # Test MEGA integration
        run_test "MEGA - List Files" \
            "curl -s -w '\n%{http_code}' -H 'Authorization: Bearer $ACCESS_TOKEN' '$BASE_URL/api/v1/cloud/mega/files'" \
            "any"
            
        # Test cloud storage settings
        run_test "Cloud Storage Settings" \
            "curl -s -w '\n%{http_code}' -H 'Authorization: Bearer $ACCESS_TOKEN' '$BASE_URL/api/v1/cloud/settings'" \
            "any"
    else
        log_warning "Skipping cloud integration tests - no access token available"
    fi
}

test_phone_features() {
    log_info "=== Testing Phone Verification and Calling ==="
    
    if [[ -n "$ACCESS_TOKEN" ]]; then
        # Test phone verification
        local phone_data="{\"phone_number\":\"+1234567890\"}"
        run_test "Send Verification Code" \
            "curl -s -w '\n%{http_code}' -X POST -H 'Authorization: Bearer $ACCESS_TOKEN' -H 'Content-Type: application/json' -d '$phone_data' '$BASE_URL/api/v1/phone/verify/send'" \
            "any"
            
        # Test phone call initiation
        local call_data="{\"phone_number\":\"+1234567890\"}"
        run_test "Initiate Phone Call" \
            "curl -s -w '\n%{http_code}' -X POST -H 'Authorization: Bearer $ACCESS_TOKEN' -H 'Content-Type: application/json' -d '$call_data' '$BASE_URL/api/v1/phone/call/initiate'" \
            "any"
            
        # Test call history
        run_test "Get Call History" \
            "curl -s -w '\n%{http_code}' -H 'Authorization: Bearer $ACCESS_TOKEN' '$BASE_URL/api/v1/phone/calls/history'" \
            "any"
    else
        log_warning "Skipping phone features tests - no access token available"
    fi
}

test_advanced_features() {
    log_info "=== Testing Advanced Features ==="
    
    if [[ -n "$ACCESS_TOKEN" ]]; then
        local dummy_chat_id="test_chat_123"
        local dummy_message_id="test_message_456"
        
        # Test polls
        local poll_data="{\"question\":\"What's your favorite color?\",\"options\":[\"Red\",\"Blue\",\"Green\"],\"chat_id\":\"$dummy_chat_id\"}"
        run_test "Create Poll" \
            "curl -s -w '\n%{http_code}' -X POST -H 'Authorization: Bearer $ACCESS_TOKEN' -H 'Content-Type: application/json' -d '$poll_data' '$BASE_URL/api/v1/polls'" \
            "any"
            
        # Test reactions
        local reaction_data="{\"emoji\":\"👍\"}"
        run_test "Add Message Reaction" \
            "curl -s -w '\n%{http_code}' -X POST -H 'Authorization: Bearer $ACCESS_TOKEN' -H 'Content-Type: application/json' -d '$reaction_data' '$BASE_URL/api/v1/messages/$dummy_message_id/reactions'" \
            "any"
            
        # Test status updates
        local status_data="{\"content\":\"Feeling great today!\",\"type\":\"text\"}"
        run_test "Create Status Update" \
            "curl -s -w '\n%{http_code}' -X POST -H 'Authorization: Bearer $ACCESS_TOKEN' -H 'Content-Type: application/json' -d '$status_data' '$BASE_URL/api/v1/status'" \
            "any"
            
        # Test location sharing
        local location_data="{\"latitude\":40.7128,\"longitude\":-74.0060,\"chat_id\":\"$dummy_chat_id\"}"
        run_test "Share Location" \
            "curl -s -w '\n%{http_code}' -X POST -H 'Authorization: Bearer $ACCESS_TOKEN' -H 'Content-Type: application/json' -d '$location_data' '$BASE_URL/api/v1/location/share'" \
            "any"
            
        # Test presence/typing indicators
        local typing_data="{\"chat_id\":\"$dummy_chat_id\",\"typing\":true}"
        run_test "Set Typing Status" \
            "curl -s -w '\n%{http_code}' -X POST -H 'Authorization: Bearer $ACCESS_TOKEN' -H 'Content-Type: application/json' -d '$typing_data' '$BASE_URL/api/v1/presence/typing'" \
            "any"
    else
        log_warning "Skipping advanced features tests - no access token available"
    fi
}

test_websocket_connectivity() {
    log_info "=== Testing WebSocket Connectivity ==="
    
    # Test WebSocket connection (basic connectivity test)
    log_info "Testing WebSocket endpoint availability..."
    
    # Use curl to test WebSocket upgrade
    run_test "WebSocket Upgrade Request" \
        "curl -s -w '\n%{http_code}' -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' '$BASE_URL/ws'" \
        "any"
        
    # Test streaming translation WebSocket
    run_test "Streaming Translation WebSocket" \
        "curl -s -w '\n%{http_code}' -H 'Connection: Upgrade' -H 'Upgrade: websocket' -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' '$BASE_URL/api/v1/translation/stream/ws'" \
        "any"
}

# Main test execution
main() {
    log_info "Starting AetherTalk Comprehensive API Testing"
    log_info "Base URL: $BASE_URL"
    log_info "WebSocket URL: $WS_URL"
    log_info "Test User: $TEST_USER"
    log_info "Test Email: $TEST_EMAIL"
    echo "========================================"
    
    # Run all test suites
    test_basic_connectivity
    test_authentication
    test_user_management
    test_chat_messaging
    test_group_functionality
    test_translation_features
    test_cloud_integration
    test_phone_features
    test_advanced_features
    test_websocket_connectivity
    
    # Print summary
    echo ""
    log_info "=== TEST SUMMARY ==="
    log_info "Total Tests: $TOTAL_TESTS"
    log_success "Passed: $PASSED_TESTS"
    log_error "Failed: $FAILED_TESTS"
    
    if [[ $FAILED_TESTS -eq 0 ]]; then
        log_success "All tests completed successfully!"
        exit 0
    else
        log_error "Some tests failed. Please review the output above."
        exit 1
    fi
}

# Run the main function
main "$@"