#!/bin/bash

# AetherTalk Backend Production Deployment Script
# This script handles the complete deployment process for production environments

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ENVIRONMENT=${ENVIRONMENT:-production}
DOCKER_COMPOSE_FILE=${DOCKER_COMPOSE_FILE:-docker-compose.yml}
BACKUP_DIR=${BACKUP_DIR:-./backups}
LOG_FILE=${LOG_FILE:-./deploy.log}

# Functions
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING: $1${NC}" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR: $1${NC}" | tee -a "$LOG_FILE"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date +'%Y-%m-%d %H:%M:%S')] INFO: $1${NC}" | tee -a "$LOG_FILE"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."
    
    # Check if Docker is installed and running
    if ! command -v docker &> /dev/null; then
        error "Docker is not installed. Please install Docker first."
    fi
    
    if ! docker info &> /dev/null; then
        error "Docker is not running. Please start Docker service."
    fi
    
    # Check if Docker Compose is installed
    if ! command -v docker-compose &> /dev/null; then
        error "Docker Compose is not installed. Please install Docker Compose first."
    fi
    
    # Check if required files exist
    if [[ ! -f "$DOCKER_COMPOSE_FILE" ]]; then
        error "Docker Compose file not found: $DOCKER_COMPOSE_FILE"
    fi
    
    if [[ ! -f "Dockerfile" ]]; then
        error "Dockerfile not found in current directory"
    fi
    
    log "Prerequisites check passed ✓"
}

# Create necessary directories
create_directories() {
    log "Creating necessary directories..."
    
    mkdir -p "$BACKUP_DIR"
    mkdir -p ./logs
    mkdir -p ./nginx/ssl
    mkdir -p ./monitoring
    
    log "Directories created ✓"
}

# Generate SSL certificates (self-signed for development)
generate_ssl_certificates() {
    log "Generating SSL certificates..."
    
    if [[ ! -f "./nginx/ssl/cert.pem" ]]; then
        warn "SSL certificates not found. Generating self-signed certificates for development..."
        
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout ./nginx/ssl/key.pem \
            -out ./nginx/ssl/cert.pem \
            -subj "/C=US/ST=State/L=City/O=AetherTalk/CN=localhost" \
            2>/dev/null || warn "Failed to generate SSL certificates"
        
        # Generate wildcard certificate for multi-tenant support
        openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
            -keyout ./nginx/ssl/wildcard.key.pem \
            -out ./nginx/ssl/wildcard.cert.pem \
            -subj "/C=US/ST=State/L=City/O=AetherTalk/CN=*.aethertalk.com" \
            2>/dev/null || warn "Failed to generate wildcard SSL certificates"
    fi
    
    log "SSL certificates ready ✓"
}

# Backup existing data
backup_data() {
    log "Creating backup of existing data..."
    
    BACKUP_TIMESTAMP=$(date +%Y%m%d_%H%M%S)
    BACKUP_PATH="$BACKUP_DIR/backup_$BACKUP_TIMESTAMP"
    
    mkdir -p "$BACKUP_PATH"
    
    # Backup database if container exists
    if docker ps -a --format "table {{.Names}}" | grep -q "aethertalk-postgres"; then
        log "Backing up PostgreSQL database..."
        docker exec aethertalk-postgres pg_dump -U aethertalk aethertalk > "$BACKUP_PATH/database.sql" || warn "Database backup failed"
    fi
    
    # Backup uploads if they exist
    if [[ -d "./uploads" ]]; then
        log "Backing up uploads..."
        cp -r ./uploads "$BACKUP_PATH/" || warn "Uploads backup failed"
    fi
    
    log "Backup created at: $BACKUP_PATH ✓"
}

# Build and deploy
deploy() {
    log "Starting deployment process..."
    
    # Pull latest images
    log "Pulling latest Docker images..."
    docker-compose -f "$DOCKER_COMPOSE_FILE" pull
    
    # Build the application
    log "Building AetherTalk application..."
    docker-compose -f "$DOCKER_COMPOSE_FILE" build --no-cache aethertalk
    
    # Stop existing containers
    log "Stopping existing containers..."
    docker-compose -f "$DOCKER_COMPOSE_FILE" down --remove-orphans
    
    # Start services
    log "Starting services..."
    docker-compose -f "$DOCKER_COMPOSE_FILE" up -d
    
    log "Deployment completed ✓"
}

# Health check
health_check() {
    log "Performing health checks..."
    
    # Wait for services to start
    sleep 30
    
    # Check if containers are running
    CONTAINERS=("aethertalk-backend" "aethertalk-postgres" "aethertalk-redis" "aethertalk-nginx")
    
    for container in "${CONTAINERS[@]}"; do
        if docker ps --format "table {{.Names}}" | grep -q "$container"; then
            log "Container $container is running ✓"
        else
            error "Container $container is not running ✗"
        fi
    done
    
    # Check application health endpoint
    log "Checking application health endpoint..."
    for i in {1..10}; do
        if curl -f -s http://localhost:8080/api/health > /dev/null; then
            log "Application health check passed ✓"
            break
        else
            warn "Health check attempt $i failed, retrying in 10 seconds..."
            sleep 10
        fi
        
        if [[ $i -eq 10 ]]; then
            error "Application health check failed after 10 attempts ✗"
        fi
    done
    
    # Check database connectivity
    log "Checking database connectivity..."
    if docker exec aethertalk-postgres pg_isready -U aethertalk -d aethertalk > /dev/null; then
        log "Database connectivity check passed ✓"
    else
        error "Database connectivity check failed ✗"
    fi
    
    # Check Redis connectivity
    log "Checking Redis connectivity..."
    if docker exec aethertalk-redis redis-cli ping > /dev/null; then
        log "Redis connectivity check passed ✓"
    else
        error "Redis connectivity check failed ✗"
    fi
    
    log "All health checks passed ✓"
}

# Show deployment status
show_status() {
    log "Deployment Status:"
    echo ""
    
    info "Running Containers:"
    docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
    echo ""
    
    info "Service URLs:"
    echo "  • Main Application: https://localhost"
    echo "  • API Endpoint: https://localhost/api"
    echo "  • WebSocket: wss://localhost/ws"
    echo "  • Health Check: http://localhost:8080/api/health"
    echo ""
    
    info "Database Connection:"
    echo "  • Host: localhost"
    echo "  • Port: 5432"
    echo "  • Database: aethertalk"
    echo "  • User: aethertalk"
    echo ""
    
    info "Redis Connection:"
    echo "  • Host: localhost"
    echo "  • Port: 6379"
    echo ""
    
    info "Logs:"
    echo "  • Application: docker logs aethertalk-backend"
    echo "  • Database: docker logs aethertalk-postgres"
    echo "  • Redis: docker logs aethertalk-redis"
    echo "  • Nginx: docker logs aethertalk-nginx"
    echo ""
}

# Rollback function
rollback() {
    warn "Rolling back deployment..."
    
    # Stop current containers
    docker-compose -f "$DOCKER_COMPOSE_FILE" down
    
    # Find latest backup
    LATEST_BACKUP=$(ls -t "$BACKUP_DIR" | head -n1)
    
    if [[ -n "$LATEST_BACKUP" ]]; then
        log "Restoring from backup: $LATEST_BACKUP"
        
        # Restore database
        if [[ -f "$BACKUP_DIR/$LATEST_BACKUP/database.sql" ]]; then
            docker-compose -f "$DOCKER_COMPOSE_FILE" up -d postgres
            sleep 10
            docker exec -i aethertalk-postgres psql -U aethertalk aethertalk < "$BACKUP_DIR/$LATEST_BACKUP/database.sql"
        fi
        
        # Restore uploads
        if [[ -d "$BACKUP_DIR/$LATEST_BACKUP/uploads" ]]; then
            rm -rf ./uploads
            cp -r "$BACKUP_DIR/$LATEST_BACKUP/uploads" ./
        fi
        
        log "Rollback completed ✓"
    else
        error "No backup found for rollback"
    fi
}

# Cleanup old backups
cleanup_backups() {
    log "Cleaning up old backups..."
    
    # Keep only last 5 backups
    cd "$BACKUP_DIR"
    ls -t | tail -n +6 | xargs -r rm -rf
    cd - > /dev/null
    
    log "Backup cleanup completed ✓"
}

# Main deployment function
main() {
    log "Starting AetherTalk Backend Deployment"
    log "Environment: $ENVIRONMENT"
    log "Docker Compose File: $DOCKER_COMPOSE_FILE"
    
    case "${1:-deploy}" in
        "deploy")
            check_prerequisites
            create_directories
            generate_ssl_certificates
            backup_data
            deploy
            health_check
            show_status
            cleanup_backups
            log "Deployment completed successfully! 🚀"
            ;;
        "rollback")
            rollback
            ;;
        "status")
            show_status
            ;;
        "health")
            health_check
            ;;
        "backup")
            backup_data
            ;;
        "logs")
            docker-compose -f "$DOCKER_COMPOSE_FILE" logs -f
            ;;
        "stop")
            log "Stopping all services..."
            docker-compose -f "$DOCKER_COMPOSE_FILE" down
            log "All services stopped ✓"
            ;;
        "restart")
            log "Restarting all services..."
            docker-compose -f "$DOCKER_COMPOSE_FILE" restart
            health_check
            log "All services restarted ✓"
            ;;
        *)
            echo "Usage: $0 {deploy|rollback|status|health|backup|logs|stop|restart}"
            echo ""
            echo "Commands:"
            echo "  deploy   - Full deployment (default)"
            echo "  rollback - Rollback to previous version"
            echo "  status   - Show deployment status"
            echo "  health   - Run health checks"
            echo "  backup   - Create backup"
            echo "  logs     - Show application logs"
            echo "  stop     - Stop all services"
            echo "  restart  - Restart all services"
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"