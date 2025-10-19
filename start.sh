#!/bin/bash

# AetherTalk Quick Start Script

set -e

echo "🚀 Starting AetherTalk Enterprise Messaging Platform"
echo "=================================================="

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Please install Docker first."
    exit 1
fi

# Check if Docker Compose is installed
if ! command -v docker-compose &> /dev/null; then
    echo "❌ Docker Compose is not installed. Please install Docker Compose first."
    exit 1
fi

# Create necessary directories
echo "📁 Creating directories..."
mkdir -p priv/media
mkdir -p log

# Start services with Docker Compose
echo "🐳 Starting services with Docker Compose..."
docker-compose up -d

# Wait for services to be healthy
echo "⏳ Waiting for services to be ready..."
sleep 10

# Check service health
echo "🔍 Checking service health..."
docker-compose ps

# Show service URLs
echo ""
echo "✅ AetherTalk is now running!"
echo "================================"
echo "🌐 HTTP API:      http://localhost:8080"
echo "🔌 WebSocket:     ws://localhost:8081/ws"
echo "💾 PostgreSQL:    localhost:5432"
echo "🗄️  Redis:        localhost:6379"
echo ""
echo "📊 Health Check:  http://localhost:8080/health"
echo "📈 Metrics:       http://localhost:8080/metrics"
echo ""
echo "📚 API Documentation: See README.md"
echo ""
echo "To stop the services, run: docker-compose down"
echo "To view logs, run: docker-compose logs -f"