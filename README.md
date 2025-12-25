# Acquisitions Service – Docker & Neon Setup

This project is a Node.js/Express service using Neon as the Postgres database.
It is dockerized to support:

- **Local development** with **Neon Local** for ephemeral branches
- **Production** with **Neon Cloud (serverless Postgres)**

The app always connects to the database via the `DATABASE_URL` environment variable.

---

## 1. Environment Files

### 1.1 Development: `.env.development`

Create `.env.development` in the project root (or edit the one already here) with at least:

```env
PORT=3000
NODE_ENV=development
LOG_LEVEL=debug

# Neon Local Postgres endpoint inside docker network
DATABASE_URL=postgresql://neon:npg@neon-local:5432/neondb?sslmode=require

# Neon Local configuration
NEON_API_KEY=your_neon_api_key_here
NEON_PROJECT_ID=your_neon_project_id_here
PARENT_BRANCH_ID=your_parent_branch_id_here
# DELETE_BRANCH=false  # optional: persist branches
```

### 1.2 Production: `.env.production`

Create `.env.production` in the project root with your production Neon cloud URL:

```env
PORT=3000
NODE_ENV=production
LOG_LEVEL=info

DATABASE_URL=postgresql://user:password@ep-your-project-id.region.aws.neon.tech/neondb?sslmode=require
```

> **Important:** Do **not** commit `.env.development`, `.env.production`, or `.env` to version control.

---

## 2. Running Locally with Neon Local (Development)

1. Ensure Docker is running.
2. Make sure `.env.development` is configured as above.
3. Start the dev stack (app + Neon Local):

   ```bash
   docker compose -f docker-compose.dev.yml up --build
   ```

   This will:

   - Start the `neon-local` service on `localhost:5432` and `neon-local:5432` inside the Docker network.
   - Start the `acquisitions-app-dev` container on `localhost:3000`.

4. Access the app at:

   - http://localhost:3000

5. To stop:

   ```bash
   docker compose -f docker-compose.dev.yml down
   ```

### Notes on Neon Local

- Neon Local will create **ephemeral branches** from `PARENT_BRANCH_ID` each time the container starts.
- Branches are deleted on shutdown unless you set `DELETE_BRANCH=false`.
- The app connects using `DATABASE_URL` and does **not** need to know about branches directly.

---

## 3. Running with Neon Cloud (Production-style)

In production, the app connects directly to Neon\'s serverless Postgres endpoint.

1. Ensure `.env.production` contains your Neon production `DATABASE_URL`.
2. Build and run using the production compose file:

   ```bash
   docker compose -f docker-compose.prod.yml up --build -d
   ```

3. The app will start in `NODE_ENV=production` and use the Neon cloud database.
4. To stop:

   ```bash
   docker compose -f docker-compose.prod.yml down
   ```

---

## 4. Migrations with Drizzle

The project uses Drizzle for schema management.

To run migrations against whichever database `DATABASE_URL` points to:

```bash
npm run db:migrate
```

You can run this:

- Directly on your host (using `.env` / `.env.development` / `.env.production`)
- Inside a container, for example in development:

```bash
docker exec -it acquisitions-app-dev npm run db:migrate
```

---

## 5. Summary

- **Dev:** `docker-compose.dev.yml` runs the app + Neon Local. `DATABASE_URL` targets `postgresql://neon:npg@neon-local:5432/neondb?...`.
- **Prod:** `docker-compose.prod.yml` runs only the app. `DATABASE_URL` targets your real `...neon.tech...` connection string.
- The app code always reads from `process.env.DATABASE_URL` (via `dotenv` / environment), so switching environments is configuration-only.
