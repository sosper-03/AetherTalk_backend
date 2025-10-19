# AetherTalk Dockerfile
FROM erlang:24-alpine AS builder

# Install build dependencies
RUN apk add --no-cache git

# Set working directory
WORKDIR /app

# Copy rebar3 configuration
COPY rebar.config rebar.lock ./

# Copy source code
COPY src/ src/
COPY include/ include/
COPY priv/ priv/
COPY config/ config/

# Get dependencies and compile
RUN rebar3 get-deps
RUN rebar3 compile
RUN rebar3 release

# Production stage
FROM alpine:3.16

# Install runtime dependencies
RUN apk add --no-cache \
    ncurses-libs \
    libstdc++ \
    openssl \
    ca-certificates

# Create app user
RUN addgroup -g 1000 aethertalk && \
    adduser -D -s /bin/sh -u 1000 -G aethertalk aethertalk

# Set working directory
WORKDIR /app

# Copy release from builder stage
COPY --from=builder /app/_build/default/rel/aethertalk ./
COPY --from=builder /app/priv/schema.sql ./priv/

# Change ownership
RUN chown -R aethertalk:aethertalk /app

# Switch to app user
USER aethertalk

# Expose ports
EXPOSE 8080 8081

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

# Start the application
CMD ["./bin/aethertalk", "foreground"]