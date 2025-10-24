#!/bin/bash

# AetherTalk Application Startup Script
# Starts the AetherTalk application with proper configuration

set -e

# Configuration
CONFIG_FILE="${AETHERTALK_CONFIG:-config/sys.config}"
CLOUD_CONFIG="${AETHERTALK_CLOUD_CONFIG:-config/cloud.config}"
ENV_FILE="${AETHERTALK_ENV_FILE:-.env}"
CLOUD_ENV_FILE="${AETHERTALK_CLOUD_ENV_FILE:-.env.cloud}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Load environment variables
load_env() {
    if [ -f "$CLOUD_ENV_FILE" ]; then
        log_info "Loading cloud environment from $CLOUD_ENV_FILE"
        set -a
        source "$CLOUD_ENV_FILE"
        set +a
    elif [ -f "$ENV_FILE" ]; then
        log_info "Loading environment from $ENV_FILE"
        set -a
        source "$ENV_FILE"
        set +a
    else
        log_warning "No environment file found. Using default configuration."
    fi
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check Erlang/OTP
    if ! command -v erl &> /dev/null; then
        log_error "Erlang/OTP is not installed"
        exit 1
    fi
    
    # Check rebar3
    if ! command -v rebar3 &> /dev/null; then
        log_error "rebar3 is not installed"
        exit 1
    fi
    
    # Check if project is compiled
    if [ ! -d "_build/default/lib" ]; then
        log_info "Project not compiled. Compiling now..."
        rebar3 compile
    fi
    
    log_success "Prerequisites check passed"
}

# Setup directories
setup_directories() {
    log_info "Setting up directories..."
    
    # Create necessary directories
    mkdir -p logs
    mkdir -p data/mnesia
    mkdir -p media
    mkdir -p tmp
    
    log_success "Directories created"
}

# Check database connectivity
check_database() {
    log_info "Checking database connectivity..."
    
    local db_host="${AETHERTALK_DB_HOST:-localhost}"
    local db_port="${AETHERTALK_DB_PORT:-5432}"
    local db_user="${AETHERTALK_DB_USER:-aethertalk}"
    local db_pass="${AETHERTALK_DB_PASS:-aethertalk_password}"
    local db_name="${AETHERTALK_DB_NAME:-aethertalk}"
    
    if command -v psql &> /dev/null; then
        if PGPASSWORD="$db_pass" psql -h "$db_host" -p "$db_port" -U "$db_user" -d "$db_name" -c "SELECT 1;" > /dev/null 2>&1; then
            log_success "Database connection successful"
        else
            log_warning "Database connection failed. Application may not work properly."
            log_info "Run './setup_database.sh' to set up the database"
        fi
    else
        log_warning "PostgreSQL client not available. Cannot test database connection."
    fi
}

# Check Redis connectivity
check_redis() {
    log_info "Checking Redis connectivity..."
    
    local redis_host="${AETHERTALK_REDIS_HOST:-localhost}"
    local redis_port="${AETHERTALK_REDIS_PORT:-6379}"
    
    if command -v redis-cli &> /dev/null; then
        if redis-cli -h "$redis_host" -p "$redis_port" ping > /dev/null 2>&1; then
            log_success "Redis connection successful"
        else
            log_warning "Redis connection failed. Caching and real-time features may not work."
        fi
    else
        log_warning "Redis client not available. Cannot test Redis connection."
    fi
}

# Start the application
start_application() {
    local mode="${1:-shell}"
    local config_file="$CONFIG_FILE"
    
    # Use cloud config if available and requested
    if [ "$AETHERTALK_USE_CLOUD_CONFIG" = "true" ] && [ -f "$CLOUD_CONFIG" ]; then
        config_file="$CLOUD_CONFIG"
        log_info "Using cloud configuration: $config_file"
    else
        log_info "Using configuration: $config_file"
    fi
    
    case "$mode" in
        "shell")
            log_info "Starting AetherTalk in development mode (shell)..."
            rebar3 shell --config "$config_file"
            ;;
        "daemon")
            log_info "Starting AetherTalk in daemon mode..."
            rebar3 release
            _build/default/rel/aethertalk/bin/aethertalk start
            ;;
        "foreground")
            log_info "Starting AetherTalk in foreground mode..."
            rebar3 release
            _build/default/rel/aethertalk/bin/aethertalk foreground
            ;;
        *)
            log_error "Unknown mode: $mode"
            log_info "Available modes: shell, daemon, foreground"
            exit 1
            ;;
    esac
}

# Stop the application
stop_application() {
    log_info "Stopping AetherTalk application..."
    
    # Try to stop gracefully
    if [ -f "_build/default/rel/aethertalk/bin/aethertalk" ]; then
        _build/default/rel/aethertalk/bin/aethertalk stop
    fi
    
    # Kill any remaining beam processes
    pkill -f "aethertalk" || true
    
    log_success "Application stopped"
}

# Show status
show_status() {
    log_info "Checking AetherTalk application status..."
    
    # Check if beam process is running
    if pgrep -f "aethertalk" > /dev/null; then
        log_success "AetherTalk is running"
        
        # Show process info
        ps aux | grep -E "(beam|aethertalk)" | grep -v grep
        
        # Test health endpoint
        if command -v curl &> /dev/null; then
            local port="${AETHERTALK_HTTP_PORT:-8080}"
            if curl -s "http://localhost:$port/health" > /dev/null 2>&1; then
                log_success "Health endpoint is responding"
            else
                log_warning "Health endpoint is not responding"
            fi
        fi
    else
        log_info "AetherTalk is not running"
    fi
}

# Show help
show_help() {
    echo "AetherTalk Application Startup Script"
    echo
    echo "Usage: $0 [command] [options]"
    echo
    echo "Commands:"
    echo "  start [mode]   Start the application (default: shell)"
    echo "  stop           Stop the application"
    echo "  restart [mode] Restart the application"
    echo "  status         Show application status"
    echo "  test           Run comprehensive tests"
    echo "  setup-db       Set up the database"
    echo "  help           Show this help message"
    echo
    echo "Modes:"
    echo "  shell          Start in development shell mode (default)"
    echo "  daemon         Start as daemon in background"
    echo "  foreground     Start in foreground mode"
    echo
    echo "Environment variables:"
    echo "  AETHERTALK_CONFIG           Configuration file (default: config/sys.config)"
    echo "  AETHERTALK_CLOUD_CONFIG     Cloud configuration file (default: config/cloud.config)"
    echo "  AETHERTALK_ENV_FILE         Environment file (default: .env)"
    echo "  AETHERTALK_CLOUD_ENV_FILE   Cloud environment file (default: .env.cloud)"
    echo "  AETHERTALK_USE_CLOUD_CONFIG Use cloud configuration (true/false)"
    echo
    echo "Examples:"
    echo "  $0 start shell              # Start in development mode"
    echo "  $0 start daemon             # Start as daemon"
    echo "  $0 stop                     # Stop the application"
    echo "  $0 restart foreground       # Restart in foreground mode"
    echo "  $0 test                     # Run comprehensive tests"
}

# Main function
main() {
    local command="${1:-start}"
    local mode="${2:-shell}"
    
    case "$command" in
        "start")
            echo "=========================================="
            echo "🚀 Starting AetherTalk Application"
            echo "=========================================="
            echo
            
            load_env
            check_prerequisites
            setup_directories
            check_database
            check_redis
            
            echo
            start_application "$mode"
            ;;
        "stop")
            echo "=========================================="
            echo "🛑 Stopping AetherTalk Application"
            echo "=========================================="
            echo
            
            stop_application
            ;;
        "restart")
            echo "=========================================="
            echo "🔄 Restarting AetherTalk Application"
            echo "=========================================="
            echo
            
            stop_application
            sleep 2
            load_env
            check_prerequisites
            setup_directories
            start_application "$mode"
            ;;
        "status")
            echo "=========================================="
            echo "📊 AetherTalk Application Status"
            echo "=========================================="
            echo
            
            show_status
            ;;
        "test")
            echo "=========================================="
            echo "🧪 Running AetherTalk Tests"
            echo "=========================================="
            echo
            
            if [ -f "comprehensive_test.sh" ]; then
                ./comprehensive_test.sh
            else
                log_error "Test script not found"
                exit 1
            fi
            ;;
        "setup-db")
            echo "=========================================="
            echo "🗄️  Setting up AetherTalk Database"
            echo "=========================================="
            echo
            
            load_env
            if [ -f "setup_database.sh" ]; then
                ./setup_database.sh
            else
                log_error "Database setup script not found"
                exit 1
            fi
            ;;
        "help"|"--help"|"-h")
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            echo
            show_help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"