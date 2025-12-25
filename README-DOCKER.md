# Acquisitions App - Docker Setup with Neon Database

This guide explains how to run the Acquisitions application using Docker with Neon Database for both development and production environments.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Environment Setup](#environment-setup)
- [Development Environment (Local with Neon Local)](#development-environment-local-with-neon-local)
- [Production Environment (Neon Cloud)](#production-environment-neon-cloud)
- [Database Migration](#database-migration)
- [Troubleshooting](#troubleshooting)
- [Architecture Overview](#architecture-overview)

## Prerequisites

- **Docker** (v20.10 or later)
- **Docker Compose** (v2.0 or later)
- **Neon Account** (sign up at [neon.tech](https://neon.tech))
- **Git** (for branch persistence in development)

## Environment Setup

### 1. Clone and Setup

```bash
git clone <your-repository>
cd acquisitions
```

### 2. Get Neon Credentials

Visit your [Neon Console](https://console.neon.tech/) and collect:

1. **API Key**: Account Settings → Developer Settings → API Keys
2. **Project ID**: Project Settings → General → Project ID
3. **Branch ID**: Branches → Main branch (or your preferred parent branch)
4. **Connection String**: Dashboard → Connection Details

### 3. Configure Environment Files

Copy the example environment file:
```bash
cp .env.example .env.development
cp .env.example .env.production
```

#### Development Configuration (`.env.development`)

```env
# Server Configuration
PORT=3000
NODE_ENV=development
LOG_LEVEL=debug

# Database Configuration - Neon Local
DATABASE_URL=postgresql://neon:npg@neon-local:5432/neondb?sslmode=require

# Neon Local Configuration
NEON_API_KEY=your_actual_neon_api_key
NEON_PROJECT_ID=your_actual_project_id
PARENT_BRANCH_ID=your_parent_branch_id
```

#### Production Configuration (`.env.production`)

```env
# Server Configuration
PORT=3000
NODE_ENV=production
LOG_LEVEL=info

# Database Configuration - Neon Cloud
DATABASE_URL=postgresql://user:password@ep-your-project.region.aws.neon.tech/neondb?sslmode=require
```

## Development Environment (Local with Neon Local)

### Architecture

In development, the setup uses:
- **Neon Local**: A Docker proxy that creates ephemeral branches
- **Your App**: Connects to Neon Local as if it's a regular Postgres database
- **Automatic Branching**: Each startup creates a fresh database branch

### Start Development Environment

```bash
# Start both Neon Local and your app
docker-compose -f docker-compose.dev.yml up --build

# Or run in detached mode
docker-compose -f docker-compose.dev.yml up -d --build
```

### What Happens

1. **Neon Local** starts and creates an ephemeral branch from your parent branch
2. **Your app** connects to `neon-local:5432` inside the Docker network
3. **Database migrations** can be run against the ephemeral branch
4. **Branch cleanup** happens automatically when containers stop

### Development Commands

```bash
# View logs
docker-compose -f docker-compose.dev.yml logs -f

# Run database migrations
docker-compose -f docker-compose.dev.yml exec app npm run db:migrate

# Open Drizzle Studio (if available)
docker-compose -f docker-compose.dev.yml exec app npm run db:studio

# Stop services
docker-compose -f docker-compose.dev.yml down

# Stop and remove volumes
docker-compose -f docker-compose.dev.yml down -v
```

### Persistent Branches (Optional)

To persist branches across container restarts, uncomment in `.env.development`:
```env
DELETE_BRANCH=false
```

This creates a `.neon_local/` directory to store branch metadata.

## Production Environment (Neon Cloud)

### Architecture

In production, the setup uses:
- **Neon Cloud Database**: Your actual serverless Postgres database
- **Direct Connection**: No proxy, direct connection to Neon's cloud infrastructure
- **Production Optimizations**: Resource limits, health checks, and logging

### Deploy Production Environment

```bash
# Start production environment
docker-compose -f docker-compose.prod.yml up --build

# Or run in detached mode
docker-compose -f docker-compose.prod.yml up -d --build
```

### Production Commands

```bash
# View logs
docker-compose -f docker-compose.prod.yml logs -f

# Check health status
docker-compose -f docker-compose.prod.yml ps

# Scale application (if needed)
docker-compose -f docker-compose.prod.yml up --scale app=3

# Stop production services
docker-compose -f docker-compose.prod.yml down
```

### Production Considerations

1. **Resource Limits**: CPU and memory limits are configured
2. **Health Checks**: Automatic health monitoring on `/health` endpoint
3. **Restart Policy**: Containers restart automatically unless stopped
4. **Security**: Non-root user, no new privileges
5. **Logging**: JSON logs with rotation

## Database Migration

### Development Migrations

```bash
# Generate migration files
docker-compose -f docker-compose.dev.yml exec app npm run db:generate

# Run migrations
docker-compose -f docker-compose.dev.yml exec app npm run db:migrate
```

### Production Migrations

**Important**: Always test migrations in development first!

```bash
# Run production migrations
docker-compose -f docker-compose.prod.yml exec app npm run db:migrate

# Or run as a one-off container
docker-compose -f docker-compose.prod.yml run --rm app npm run db:migrate
```

## Troubleshooting

### Common Issues

#### 1. Neon Local Connection Failed

```
Error: connect ECONNREFUSED 127.0.0.1:5432
```

**Solution**: Ensure Neon Local container is healthy:
```bash
docker-compose -f docker-compose.dev.yml ps
docker-compose -f docker-compose.dev.yml logs neon-local
```

#### 2. Invalid Neon Credentials

```
Error: API key is invalid
```

**Solution**: Verify your Neon credentials in `.env.development`:
- Check API key in Neon Console
- Ensure Project ID is correct
- Verify Branch ID exists

#### 3. SSL Connection Issues

```
Error: SSL connection failed
```

**Solution**: For JavaScript applications, ensure SSL configuration:
```javascript
// In your database connection
ssl: { rejectUnauthorized: false }
```

#### 4. Permission Denied in Container

```
Error: EACCES: permission denied
```

**Solution**: Check file permissions or run:
```bash
docker-compose -f docker-compose.dev.yml down -v
docker-compose -f docker-compose.dev.yml up --build
```

### Health Checks

Check application health:
```bash
# Development
curl http://localhost:3000/health

# Inside Docker network
docker-compose -f docker-compose.dev.yml exec app curl http://localhost:3000/health
```

### Logs and Debugging

```bash
# Application logs
docker-compose -f docker-compose.dev.yml logs -f app

# Neon Local logs
docker-compose -f docker-compose.dev.yml logs -f neon-local

# All logs
docker-compose -f docker-compose.dev.yml logs -f

# Follow specific service
docker logs -f acquisitions-app-dev
```

## Architecture Overview

### Development Flow
```
Developer Code → Docker Compose Dev → Neon Local → Ephemeral Branch → Neon Cloud
                     ↓
                 App Container
```

### Production Flow
```
Production Code → Docker Compose Prod → App Container → Neon Cloud Database
```

### Environment Variables Flow

| Environment | DATABASE_URL | Neon Service | Branch Type |
|-------------|--------------|--------------|-------------|
| Development | `neon-local:5432` | Neon Local Proxy | Ephemeral |
| Production  | `neon.tech` endpoint | Direct Cloud | Persistent |

### File Structure

```
acquisitions/
├── Dockerfile                 # Multi-stage build
├── docker-compose.dev.yml     # Development with Neon Local
├── docker-compose.prod.yml    # Production with Neon Cloud
├── .env.development           # Dev environment variables
├── .env.production            # Prod environment variables
├── .env.example               # Template for env files
├── .dockerignore              # Docker build exclusions
├── .neon_local/              # Neon Local metadata (git-ignored)
└── src/                      # Application source code
```

## Security Notes

1. **Never commit** `.env.development` or `.env.production` files
2. **Use environment variables** for all secrets in production
3. **Rotate API keys** regularly
4. **Use least-privilege** database users
5. **Monitor access logs** in Neon Console

## Performance Tips

1. **Use connection pooling** in production
2. **Monitor branch usage** in Neon Console
3. **Clean up unused branches** regularly
4. **Use prepared statements** for queries
5. **Implement proper indexing** strategies

---

## Quick Reference

### Development Startup
```bash
cp .env.example .env.development
# Edit .env.development with your Neon credentials
docker-compose -f docker-compose.dev.yml up --build
```

### Production Deployment
```bash
cp .env.example .env.production
# Edit .env.production with your Neon production URL
docker-compose -f docker-compose.prod.yml up -d --build
```

### Stop All Services
```bash
# Development
docker-compose -f docker-compose.dev.yml down

# Production
docker-compose -f docker-compose.prod.yml down
```

For more information, visit:
- [Neon Documentation](https://neon.tech/docs)
- [Neon Local Guide](https://neon.tech/docs/local/neon-local)
- [Docker Compose Documentation](https://docs.docker.com/compose/)