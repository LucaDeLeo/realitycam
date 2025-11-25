# Build stage - use Rust nightly for edition2024 support
FROM rustlang/rust:nightly-bookworm AS builder

WORKDIR /app

# Install dependencies for c2pa-rs
RUN apt-get update && apt-get install -y \
    pkg-config \
    libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Copy manifests
COPY Cargo.toml Cargo.lock ./

# Create dummy src to cache dependencies
RUN mkdir src && echo "fn main() {}" > src/main.rs

# Enable SQLx offline mode (uses cached query metadata)
ENV SQLX_OFFLINE=true

# Build dependencies (this layer is cached)
RUN cargo build --release && rm -rf src

# Copy actual source
COPY src ./src
COPY .sqlx ./.sqlx
COPY migrations ./migrations
COPY certs ./certs

# Build the application
RUN touch src/main.rs && cargo build --release

# Runtime stage
FROM debian:bookworm-slim

WORKDIR /app

# Install runtime dependencies
RUN apt-get update && apt-get install -y \
    ca-certificates \
    libssl3 \
    && rm -rf /var/lib/apt/lists/*

# Copy binary from builder
COPY --from=builder /app/target/release/realitycam-api .

# Copy migrations and certs
COPY --from=builder /app/migrations ./migrations
COPY --from=builder /app/certs ./certs

# Expose port
EXPOSE 8080

# Run the binary
CMD ["./realitycam-api"]
