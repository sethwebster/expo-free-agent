FROM oven/bun:1.1-alpine AS builder

WORKDIR /app

# Install all dependencies (including dev) for build
COPY package.json bun.lock* ./
RUN bun install --frozen-lockfile

# Copy source files
COPY src ./src

# Build
RUN bun run build

# Copy SQL schema to dist
RUN cp /app/src/db/schema.sql /app/dist/schema.sql

# Production stage
FROM oven/bun:1.1-alpine AS production

WORKDIR /app

# Copy built files from builder
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/package.json ./package.json

# Install only production dependencies
RUN bun install --frozen-lockfile --production

# Create data and storage directories
RUN mkdir -p /app/data /app/storage

# Expose port
EXPOSE 3000

# Set environment variables
ENV NODE_ENV=production
ENV PORT=3000
ENV CONTROLLER_URL=http://localhost:3000
ENV CONTROLLER_API_KEY=change-me-in-production

# Start server
CMD ["bun", "run", "dist/cli.js"]
