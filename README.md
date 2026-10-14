# dcomp_server

Elixir / Phoenix LiveView app (OTP app `:dcomp`). Run `make help` for all targets.

## Local development
1. `make start` runs the local stack (postgres, redis, pgadmin) via Tilt / `docker-compose.yml`.
2. `cp .env.example .env`, then `make setup` and `make server` (http://localhost:4000).
3. `make test`, `make check` (format, credo, dialyzer).

## Docker
`make docker.build` / `make docker.release` build and run the release image
(`devops/builder/Dockerfile`) against the `dcomp_server_storage` network using `.env.prod`.

## Local stack & ops (formerly dcomp_devops)

Local dev stack (postgres, redis, pgadmin) and ops helpers. Run `make help` for all targets.

## Decomp tracker

Tracks community decompilation projects (claims, solves, ranking, a picture revealed piece by piece).

**How it works.** Each game's repo is mirrored with `git` (no GitHub API, so no rate limits) and read
every `poll_interval_s` seconds; the repo is the source of truth. A GitHub Action can ask for an early
sync, but the payload is never trusted: the server re-reads the repo itself. Identity is the GitHub
login found in `pool/claims/*`; no emails are stored.

**First run**
1. Register on the site, then promote yourself:
   `bin/dcomp eval 'Dcomp.Release.make_admin("you@example.com")'` (or `Dcomp.Accounts.make_admin/1` in `iex`).
2. *Admin → Games → Add game*: name, `https://` repo URL, branch, optional puzzle image.
3. *Admin → Settings*: generate the API key, set the poll interval and the puzzle layout
   (pieces sized by function size, or equal pieces).

**Webhook** (add to the game repo's workflow, key stored as the secret `DCOMP_API_KEY`):

```yaml
- name: Notify dcomp
  if: always()
  run: >
    curl -fsS -X POST
    -H "Authorization: Bearer ${{ secrets.DCOMP_API_KEY }}"
    https://YOUR-HOST/api/games/GAME-SLUG/sync
```

**Environment**

| Var | Default | Purpose |
|---|---|---|
| `MIRROR_DIR` | `priv/mirrors` | bare git mirrors, one per game; can be rebuilt, so losing it only costs a re-clone |
| `UPLOADS_PATH` | `priv/static/uploads` | puzzle images; **not rebuildable** |

In containers both live on the container's disk unless you mount a volume, and uploads are lost on
redeploy. Point them at a persistent mount, e.g. `MIRROR_DIR=/data/mirrors UPLOADS_PATH=/data/uploads`
with a volume on `/data` (on dokku: `dokku storage:mount <app> /host/path:/data`). The runtime image
needs `git` (it is installed in `devops/builder/Dockerfile`).

**Running tests:** `.env` exports `MIX_ENV=dev`, so use `MIX_ENV=test mix test`.
