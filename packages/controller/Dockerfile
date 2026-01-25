FROM oven/bun:1.1-alpine AS base

WORKDIR /app

# Install dependencies
COPY package.json bun.lock* ./
RUN bun install --frozen-lockfile --production

# Copy source
COPY . .

# Build
RUN bun run build

# Copy SQL schema files to dist (bun bundler doesn't include them)
RUN mkdir -p /app/dist
RUN cp /app/src/db/schema.sql /app/dist/schema.sql

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
