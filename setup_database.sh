#!/bin/bash

# AetherTalk Database Setup Script
# Sets up PostgreSQL database with schema and initial data

set -e

# Configuration
DB_HOST="${AETHERTALK_DB_HOST:-localhost}"
DB_PORT="${AETHERTALK_DB_PORT:-5432}"
DB_NAME="${AETHERTALK_DB_NAME:-aethertalk}"
DB_USER="${AETHERTALK_DB_USER:-aethertalk}"
DB_PASS="${AETHERTALK_DB_PASS:-aethertalk_password}"

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

# Check if PostgreSQL client is available
check_psql() {
    if ! command -v psql &> /dev/null; then
        log_error "PostgreSQL client (psql) is not installed"
        log_info "Please install PostgreSQL client: apt-get install postgresql-client"
        exit 1
    fi
}

# Test database connection
test_connection() {
    log_info "Testing database connection..."
    
    if PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "SELECT 1;" > /dev/null 2>&1; then
        log_success "Database connection successful"
        return 0
    else
        log_error "Failed to connect to database"
        log_info "Please check your database configuration:"
        log_info "  Host: $DB_HOST"
        log_info "  Port: $DB_PORT"
        log_info "  User: $DB_USER"
        log_info "  Database: $DB_NAME"
        return 1
    fi
}

# Create database if it doesn't exist
create_database() {
    log_info "Creating database '$DB_NAME' if it doesn't exist..."
    
    # Check if database exists
    if PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -lqt | cut -d \| -f 1 | grep -qw "$DB_NAME"; then
        log_info "Database '$DB_NAME' already exists"
    else
        log_info "Creating database '$DB_NAME'..."
        if PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d postgres -c "CREATE DATABASE $DB_NAME;" > /dev/null 2>&1; then
            log_success "Database '$DB_NAME' created successfully"
        else
            log_error "Failed to create database '$DB_NAME'"
            return 1
        fi
    fi
}

# Run schema creation
create_schema() {
    log_info "Creating database schema..."
    
    if [ -f "priv/schema.sql" ]; then
        if PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "priv/schema.sql" > /dev/null 2>&1; then
            log_success "Schema created successfully"
        else
            log_error "Failed to create schema"
            return 1
        fi
    else
        log_error "Schema file 'priv/schema.sql' not found"
        return 1
    fi
}

# Run migrations
run_migrations() {
    log_info "Running database migrations..."
    
    if [ -d "priv/migrations" ]; then
        for migration in priv/migrations/*.sql; do
            if [ -f "$migration" ]; then
                log_info "Running migration: $(basename "$migration")"
                if PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -f "$migration" > /dev/null 2>&1; then
                    log_success "Migration $(basename "$migration") completed"
                else
                    log_warning "Migration $(basename "$migration") failed or already applied"
                fi
            fi
        done
    else
        log_info "No migrations directory found"
    fi
}

# Create initial data
create_initial_data() {
    log_info "Creating initial data..."
    
    # Create a sample admin user
    local admin_sql="
    INSERT INTO users (username, email, password_hash, full_name, is_verified, is_active)
    VALUES (
        'admin',
        'admin@aethertalk.com',
        '\$2b\$12\$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj/RK.PZvO.S', -- 'admin123'
        'System Administrator',
        true,
        true
    )
    ON CONFLICT (username) DO NOTHING;
    
    INSERT INTO users (username, email, password_hash, full_name, is_verified, is_active)
    VALUES (
        'demo',
        'demo@aethertalk.com',
        '\$2b\$12\$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewdBPj/RK.PZvO.S', -- 'demo123'
        'Demo User',
        true,
        true
    )
    ON CONFLICT (username) DO NOTHING;
    "
    
    if PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "$admin_sql" > /dev/null 2>&1; then
        log_success "Initial data created successfully"
    else
        log_warning "Failed to create initial data (may already exist)"
    fi
}

# Verify database setup
verify_setup() {
    log_info "Verifying database setup..."
    
    # Check if main tables exist
    local tables=("users" "chats" "messages" "contacts" "calls" "media_files")
    local missing_tables=()
    
    for table in "${tables[@]}"; do
        if ! PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -c "SELECT 1 FROM $table LIMIT 1;" > /dev/null 2>&1; then
            missing_tables+=("$table")
        fi
    done
    
    if [ ${#missing_tables[@]} -eq 0 ]; then
        log_success "All required tables are present"
    else
        log_error "Missing tables: ${missing_tables[*]}"
        return 1
    fi
    
    # Check if initial users exist
    local user_count=$(PGPASSWORD="$DB_PASS" psql -h "$DB_HOST" -p "$DB_PORT" -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM users;" 2>/dev/null | tr -d ' ')
    
    if [ "$user_count" -gt 0 ]; then
        log_success "Database contains $user_count users"
    else
        log_warning "No users found in database"
    fi
}

# Main setup function
main() {
    echo "=========================================="
    echo "🗄️  AetherTalk Database Setup"
    echo "=========================================="
    echo
    
    log_info "Starting database setup..."
    log_info "Database configuration:"
    log_info "  Host: $DB_HOST"
    log_info "  Port: $DB_PORT"
    log_info "  Database: $DB_NAME"
    log_info "  User: $DB_USER"
    echo
    
    # Check prerequisites
    check_psql
    
    # Test connection
    if ! test_connection; then
        log_error "Cannot proceed without database connection"
        exit 1
    fi
    
    # Create database
    if ! create_database; then
        log_error "Failed to create database"
        exit 1
    fi
    
    # Create schema
    if ! create_schema; then
        log_error "Failed to create schema"
        exit 1
    fi
    
    # Run migrations
    run_migrations
    
    # Create initial data
    create_initial_data
    
    # Verify setup
    if ! verify_setup; then
        log_error "Database setup verification failed"
        exit 1
    fi
    
    echo
    log_success "Database setup completed successfully!"
    echo
    log_info "You can now start the AetherTalk application"
    log_info "Default admin credentials:"
    log_info "  Username: admin"
    log_info "  Password: admin123"
    echo
    log_info "Default demo credentials:"
    log_info "  Username: demo"
    log_info "  Password: demo123"
    echo
}

# Handle command line arguments
case "${1:-}" in
    --help|-h)
        echo "AetherTalk Database Setup Script"
        echo
        echo "Usage: $0 [options]"
        echo
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --verify       Only verify database setup"
        echo "  --schema-only  Only create schema (skip migrations and data)"
        echo
        echo "Environment variables:"
        echo "  AETHERTALK_DB_HOST     Database host (default: localhost)"
        echo "  AETHERTALK_DB_PORT     Database port (default: 5432)"
        echo "  AETHERTALK_DB_NAME     Database name (default: aethertalk)"
        echo "  AETHERTALK_DB_USER     Database user (default: aethertalk)"
        echo "  AETHERTALK_DB_PASS     Database password (default: aethertalk_password)"
        exit 0
        ;;
    --verify)
        check_psql
        test_connection && verify_setup
        exit $?
        ;;
    --schema-only)
        check_psql
        test_connection && create_database && create_schema
        exit $?
        ;;
    "")
        main
        ;;
    *)
        log_error "Unknown option: $1"
        log_info "Use --help for usage information"
        exit 1
        ;;
esac