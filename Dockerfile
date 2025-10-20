# Multi-stage Dockerfile for AetherTalk Backend
# Production-ready Erlang/OTP application
FROM erlang:27-alpine AS builder

# Install build dependencies
RUN apk add --no-cache \
    git \
    build-base \
    openssl-dev \
    ncurses-dev \
    wget

# Set working directory
WORKDIR /app

# Copy rebar3 configuration
COPY rebar.config rebar.lock ./

# Copy source code
COPY src/ src/
COPY include/ include/
COPY priv/ priv/
COPY test/ test/

# Build the application
RUN rebar3 get-deps
RUN rebar3 compile
RUN rebar3 as prod release

# Production stage
FROM alpine:3.18

# Install runtime dependencies
RUN apk add --no-cache \
    openssl \
    ncurses \
    libstdc++ \
    bash \
    curl \
    ca-certificates \
    wget

# Create application user
RUN addgroup -g 1000 aethertalk && \
    adduser -D -s /bin/bash -u 1000 -G aethertalk aethertalk

# Set working directory
WORKDIR /opt/aethertalk

# Copy the release from builder stage
COPY --from=builder /app/_build/prod/rel/aethertalk ./
COPY --from=builder /app/priv ./priv

# Create necessary directories
RUN mkdir -p /opt/aethertalk/logs \
             /opt/aethertalk/data \
             /opt/aethertalk/uploads \
             /opt/aethertalk/recordings && \
    chown -R aethertalk:aethertalk /opt/aethertalk

# Switch to application user
USER aethertalk

# Expose ports
EXPOSE 8080 8443 4369 9100-9200

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -f http://localhost:8080/api/health || exit 1

# Environment variables
ENV ERLANG_COOKIE=aethertalk_production_cookie
ENV NODE_NAME=aethertalk@localhost
ENV PORT=8080
ENV SSL_PORT=8443

# Start the application
CMD ["./bin/aethertalk", "foreground"]