# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Environment and setup

- This is a Node.js ESM project (`"type": "module"` in `package.json`).
- Dependencies are managed via npm.
- Environment variables are loaded via `dotenv` from `.env` (see `src/index.js` and `src/config/*.js`). At minimum, expect to configure:
  - `DATABASE_URL` – PostgreSQL connection string used by Neon + Drizzle (`src/config/database.js`, `drizzle.config.js`).
  - `JWT_SECRET` – secret key for signing JWTs (`src/utils/jwt.js`).
  - Optional: `PORT` (defaults to `3000`), `NODE_ENV`, `LOG_LEVEL` (`src/config/logger.js`).

Install dependencies before running anything:

- `npm install`

## Common commands

All commands are run from the repository root.

- Start development server (with file watching):
  - `npm run dev`
  - Entrypoint: `src/index.js` → `src/server.js` → `src/app.js`.
- Lint the codebase:
  - `npm run lint`
- Lint and automatically fix issues:
  - `npm run lint:fix`
- Format code with Prettier:
  - `npm run format`
- Check formatting only (no writes):
  - `npm run format:check`
- Database schema / migrations via Drizzle:
  - Generate SQL from models: `npm run db:generate`
  - Apply migrations: `npm run db:migrate`
  - Open Drizzle Studio: `npm run db:studio`

Tests are not currently configured: there is no `test` script in `package.json` and no test runner setup.

## High-level architecture

### Entry point and HTTP server

- `src/index.js`
  - Loads environment variables via `dotenv/config`.
  - Imports `./server.js` to start the HTTP server.
- `src/server.js`
  - Imports the Express app from `./app.js`.
  - Determines `port` from `process.env.PORT || 3000`.
  - Calls `app.listen(port, ...)` and logs a startup message.

### Express application and routing

- `src/app.js`
  - Creates the Express app and configures core middleware:
    - `helmet()` for security headers.
    - `cors()` for CORS.
    - `express.json()` / `express.urlencoded()` for body parsing.
    - `cookie-parser` for cookie support.
  - Configures request logging with `morgan('combined')`, piping output into the shared Winston logger (`#config/logger.js`).
  - Defines basic endpoints:
    - `GET /` – simple text response and log message.
    - `GET /health` – health-check JSON with uptime and timestamp.
    - `GET /api` – basic API status message.
  - Mounts feature routes:
    - `app.use('/api/auth', authRoutes)` where `authRoutes` comes from `#routes/auth.routes.js`.

### Module resolution / path aliases

`package.json` defines `imports` aliases to simplify internal imports:

- `#src/*` → `./src/*`
- `#config/*` → `./src/config/*`
- `#controllers/*` → `./src/controllers/*`
- `#middleware/*` → `./src/middleware/*`
- `#models/*` → `./src/models/*`
- `#routes/*` → `./src/routes/*`
- `#services/*` → `./src/services/*`
- `#utils/*` → `./src/utils/*`
- `#validations/*` → `./src/validations/*`

Examples:

- `import logger from '#config/logger.js';`
- `import authRoutes from '#routes/auth.routes.js';`

When adding new modules, prefer these aliases over long relative paths for consistency.

### Configuration layer

- `src/config/database.js`
  - Uses `@neondatabase/serverless` (`neon`) as the PostgreSQL driver.
  - Wraps it with `drizzle-orm/neon-http` to create a typed query builder.
  - In `NODE_ENV === 'development'`, adjusts `neonConfig` to use a local HTTP endpoint (`neon-local`) and disables secure websockets.
  - Exports:
    - `sql` – low-level Neon client.
    - `db` – Drizzle ORM instance used throughout services.
- `src/config/logger.js`
  - Central Winston logger configuration for the app.
  - Default level from `LOG_LEVEL` or `info`.
  - Uses JSON format with timestamps and error stacks; sets `defaultMeta.service = 'acquisitions-api'`.
  - File transports:
    - `logs/error.lg` for `error` level.
    - `logs/combined.log` for all logs.
  - In non-production, adds a colorized console transport for local development.
- `drizzle.config.js`
  - Drizzle CLI configuration for migrations and schema generation:
    - `schema: './src/models/*.js'` – Drizzle models are the source of truth.
    - `out: './drizzle'` – generated SQL and metadata.
    - `dialect: 'postgresql'`.
    - `dbCredentials.url` from `DATABASE_URL`.
- `drizzle/meta/*`
  - Generated Drizzle metadata (snapshot and migration journal). Treat as build artifacts; do not hand-edit.

### Data model

- `src/models/user.model.js`
  - Defines the `users` table via `drizzle-orm/pg-core`:
    - `id` – serial primary key.
    - `name` – required `varchar(255)`.
    - `email` – required unique `varchar(255)`.
    - `password` – required `varchar(255)` storing the password hash.
    - `role` – required `varchar(50)` with default `'user'`.
    - `created_at` / `updated_at` – timestamps with `defaultNow().notNull()`.
  - This schema is used by Drizzle to generate migrations and by services for queries.

### Authentication flow

Authentication is structured in layers: validation → service → controller → routes.

- Validation – `src/validations/auth.validation.js`
  - Uses `zod` to define request body schemas:
    - `signupSchema` – `name`, `email`, `password`, `role` (`'user' | 'admin'`, default `'user'`).
    - `signInSchema` – `email`, `password`.
- Services – `src/services/auth.service.js`
  - `hashPassword(password)` – bcrypt hash with a cost factor of 10; logs and wraps errors.
  - `comparePassword(password, hashedPassword)` – bcrypt compare.
  - `createUser({ name, email, password, role })`:
    - Checks for an existing user by email using Drizzle (`db.select().from(users).where(eq(users.email, email))`).
    - Throws `Error('User with this email already exists')` if found.
    - Hashes the password and inserts a new row into `users`.
    - Returns a subset of columns (id, name, email, role, created_at).
  - `authenticateUser({ email, password })`:
    - Fetches user by email.
    - Throws `Error('User not found')` if no user.
    - Compares the provided password with the stored hash.
    - Throws `Error('Invalid password')` on mismatch.
    - Returns a safe subset of user fields (no password).
- Controller – `src/controllers/auth.controller.js`
  - `signup(req, res, next)`:
    - Zod-validates the body using `signupSchema`; on failure responds with `400` and a formatted error message (`formatValidationError`).
    - Calls `createUser`, creates a JWT via `jwttoken.sign`, and stores it in a cookie using `cookies.set`.
    - Logs success and returns `201` with the created user (without password).
    - Distinguishes email conflicts: if the thrown error message is `'User with this email already exists'`, returns `409` with a conflict response.
  - `signIn(req, res, next)`:
    - Validates with `signInSchema`.
    - Calls `authenticateUser`, issues a JWT, and sets it in a cookie like `signup`.
    - Logs success and returns `200` with user details.
    - For `User not found` or `Invalid password`, returns `401` with `Invalid credentials`.
  - `signOut(req, res, next)`:
    - Clears the auth cookie via `cookies.clear`.
    - Logs success and returns `200` with a simple message.
  - All handlers delegate unexpected errors to `next(e)` so that a global error handler can respond (note: a centralized error middleware is not yet implemented in this codebase).
- Routes – `src/routes/auth.routes.js`
  - Express router that wires HTTP endpoints to the controller:
    - `POST /api/auth/sign-up` → `signup`.
    - `POST /api/auth/sign-in` → `signIn`.
    - `POST /api/auth/sign-out` → `signOut`.
  - `src/routes/users.routes.js` is currently a placeholder with no routes defined.

### Utilities

- `src/utils/jwt.js`
  - Wraps `jsonwebtoken` operations around a shared `JWT_SECRET` and a fixed expiration (`1d`).
  - `jwttoken.sign(payload)` – signs a JWT, logs and throws a generic error if signing fails.
  - `jwttoken.verify(token)` – verifies a JWT, logs and throws a generic error on failure.
- `src/utils/cookies.js`
  - Centralizes cookie behavior:
    - `getOptions()` – base options for all auth cookies:
      - `httpOnly: true`.
      - `secure: process.env.NODE_ENV === 'production'`.
      - `sameSite: 'strict'`.
      - `maxAge: 15 * 60 * 1000` (15 minutes).
    - `set(res, name, value, options?)` – sets a cookie with merged options.
    - `clear(res, name, options?)` – clears a cookie using the same base options.
    - `get(req, name)` – reads a cookie from the request.
- `src/utils/format.js`
  - `formatValidationError(errors)` – takes a Zod error object and returns a human-readable string, joining all issue messages.

### Logging behavior

- Application logging is centralized via `src/config/logger.js` and used in controllers, services, and utilities.
- HTTP access logs are produced by `morgan` in `combined` format and written through the same Winston logger.
- In development, logs appear both in the console and in files under `logs/`.

### Linting configuration

- `eslint.config.js` defines a flat ESLint configuration based on `@eslint/js` recommended rules.
- Key points:
  - Targets modern ECMAScript (ECMA 2022) and ESM (`sourceType: 'module'`).
  - Enforces 2-space indentation, single quotes, semicolons, and no unused variables (with `_`-prefixed args ignored).
  - `no-console` is disabled; logging via both `console` and the `logger` is allowed.
  - Test globals are preconfigured for `tests/**/*.js`, although no tests currently exist.
  - Ignores `node_modules/**`, `coverage/**`, `logs/**`, and `drizzle/**`.
