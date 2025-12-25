# Multi-stage build for optimal production image size
FROM node:20-alpine AS base

# Install dumb-init for proper signal handling
RUN apk add --no-cache dumb-init

# Create app directory and user for security
RUN addgroup -g 1001 -S nodejs && adduser -S nodejs -u 1001
WORKDIR /usr/src/app
RUN chown nodejs:nodejs /usr/src/app

# Development stage
FROM base AS development
ENV NODE_ENV=development
USER nodejs
COPY package*.json ./
RUN npm ci --include=dev
COPY --chown=nodejs:nodejs . .
EXPOSE 3000
CMD ["dumb-init", "npm", "run", "dev"]

# Production dependencies stage
FROM base AS dependencies
USER nodejs
COPY package*.json ./
RUN npm ci --omit=dev --frozen-lockfile && npm cache clean --force

# Production stage
FROM base AS production
ENV NODE_ENV=production
USER nodejs

# Copy dependencies from dependencies stage
COPY --from=dependencies --chown=nodejs:nodejs /usr/src/app/node_modules ./node_modules

# Copy application source
COPY --chown=nodejs:nodejs . .

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD node -e "require('http').get('http://localhost:3000/health', (res) => { process.exit(res.statusCode === 200 ? 0 : 1) }).on('error', () => process.exit(1))"

# Expose application port
EXPOSE 3000

# Use dumb-init for proper signal handling
CMD ["dumb-init", "npm", "start"]
