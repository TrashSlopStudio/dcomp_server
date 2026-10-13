#!/usr/bin/env bash
# Mirrors prod (postgres/redis) into the local docker compose stack. Wipes local data.
# Usage: bin/sync_prod.sh               # all stores, asks for confirmation
#        ONLY=pg|redis bin/sync_prod.sh
#        YES=1 bin/sync_prod.sh         # skip confirmation
# Auth: key file at $PROD_SSH_KEY, logs in as the remote user at $PROD_HOST (no passwords).
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; [ -f .env ] && . ./.env; set +a

: "${PROD_HOST:?}" "${PROD_SSH_KEY:?}" "${DB_USERNAME:?}" "${DB_DATABASE:?}" "${REDIS_PASS:?}"
PROD_PORT=${PROD_PORT:-22}
ONLY=${ONLY:-all}

prod() { ssh -i "$PROD_SSH_KEY" -o IdentitiesOnly=yes -o BatchMode=yes -p "$PROD_PORT" "dokku@$PROD_HOST" "$@"; }
dc() { docker compose exec -T "$@"; }
want() { [ "$ONLY" = all ] || [ "$ONLY" = "$1" ]; }

[ -f "$PROD_SSH_KEY" ] || { echo "missing ssh key: $PROD_SSH_KEY" >&2; exit 1; }
[ "$(stat -f %Lp "$PROD_SSH_KEY" 2>/dev/null || stat -c %a "$PROD_SSH_KEY")" = 600 ] || { echo "chmod 600 $PROD_SSH_KEY" >&2; exit 1; }
prod version >/dev/null || { echo "cannot ssh to dokku@$PROD_HOST" >&2; exit 1; }
for s in pg redis; do
  want $s || continue
  v=PROD_$(echo $s | tr a-z A-Z)_SERVICE
  : "${!v:?}"
done

echo "This WIPES local [$ONLY] data and replaces it with prod ($PROD_HOST)."
[ "${YES:-}" = 1 ] || { read -r -p "Continue? [y/N] " a </dev/tty; [ "$a" = y ]; }

if want pg; then
  echo "==> postgres"
  dc postgres dropdb --if-exists --force -U "$DB_USERNAME" "$DB_DATABASE"
  dc postgres createdb -U "$DB_USERNAME" "$DB_DATABASE"
  prod postgres:export "$PROD_PG_SERVICE" | dc postgres pg_restore --no-owner --no-acl -U "$DB_USERNAME" -d "$DB_DATABASE"
fi

if want redis; then
  echo "==> redis"
  docker compose stop redis
  prod redis:export "$PROD_REDIS_SERVICE" \
    | docker run --rm -i --volumes-from dcomp_redis_service alpine \
        sh -c 'rm -rf /data/appendonly* && cat > /data/dump.rdb'
  # appendonly=yes makes redis ignore dump.rdb, so load it with a throwaway server and rewrite the AOF from it
  img=$(docker inspect -f '{{.Config.Image}}' dcomp_redis_service)
  docker run --rm --volumes-from dcomp_redis_service "$img" sh -c '
    wait_for() { until [ "$(redis-cli info persistence | tr -d "\r" | sed -n "s/^$1://p")" = 0 ]; do
      pidof redis-server >/dev/null || { echo "temp redis died (rdb newer than local redis?)" >&2; exit 1; }; sleep 1; done; }
    redis-server --dir /data --appendonly no --save "" --daemonize yes >/dev/null
    sleep 2
    wait_for loading
    redis-cli config set appendonly yes >/dev/null
    sleep 1
    wait_for aof_rewrite_in_progress
    redis-cli shutdown nosave 2>/dev/null || true'
  docker compose start redis
fi

echo "==> done"
want pg && dc postgres psql -U "$DB_USERNAME" "$DB_DATABASE" -tc "select count(*) || ' tables' from pg_tables where schemaname='public'"
want redis && sleep 2 && dc -e REDISCLI_AUTH="$REDIS_PASS" redis redis-cli DBSIZE
exit 0
