# dcomp_server

Elixir / Phoenix LiveView app (OTP app `:dcomp`). Run `make help` for all targets.

## Local development
1. `make start` runs the local stack (postgres, redis, pgadmin) via Tilt / `docker-compose.yml`.
2. `cp .env.example .env`, then `make setup` and `make server` (http://localhost:4000).
3. `make test`, `make check` (format, credo, dialyzer).

## Docker
`make docker.build` / `make docker.release` build and run the release image
(`devops/builder/Dockerfile`) against the `dcomp_devops_storage` network using `.env.prod`.

## Local stack & ops (formerly dcomp_devops)

Local dev stack (postgres, redis, pgadmin) and ops helpers. Run `make help` for all targets.
