.PHONY: help start stop setup test

BINS_DIR = ./bin
ENV_FILE ?= .env

# add env variables if needed
ifneq (,$(wildcard ${ENV_FILE}))
	include ${ENV_FILE}
    export
endif

export GREEN=\033[0;32m
export NOFORMAT=\033[0m

# ------------------------------------------------------------------------------
# Commands
#

default: help

#🔍 check: @ Runs all code verifications
check: check.lint check.dialyzer test

#🔍 check.dialyzer: @ Runs a static code analysis
check.dialyzer: SHELL:=/bin/bash
check.dialyzer:
	@mix check.dialyzer

#🔍 check.lint: @ Strictly runs a code formatter
check.lint: SHELL:=/bin/bash
check.lint:
	@mix check.format
	@mix check.credo

#🐳 docker.build: @ Build the dcomp_app docker image
docker.build:
	@cp ./devops/builder/Dockerfile ./
	@docker build ./ -t dcomp_app
	@rm ./Dockerfile

#🐳 docker.stop: @ Stop the dcomp_app docker instance
docker.stop:
	@docker stop dcomp_app || true

#🐳 docker.delete: @ Delete the dcomp_app docker instance
docker.delete:
	@docker rm dcomp_app || true

#🐳 docker.logs: @ Show logs for the dcomp_app docker instance
docker.logs:
	@docker logs dcomp_app -f

#🐳 docker.run: @ Run the dcomp_app docker instance
docker.run: PORT:=5000
docker.run:
	@docker inspect dcomp_postgres_service >/dev/null || { echo 'Start the compose postgres first: docker compose up -d postgres redis'; exit 1; }
	@docker run --detach --name dcomp_app --network $$(docker inspect dcomp_postgres_service -f '{{range $$n, $$_ := .NetworkSettings.Networks}}{{$$n}}{{end}}') -p ${PORT}:5000 --env-file .env.prod dcomp_app

#🐳 docker.connect: @ Connect to the dcomp_app running container
docker.connect:
	@docker exec -it dcomp_app /bin/bash

#🐳 docker.release: @ Re-create a docker image and run it
docker.release: PORT:=5000
docker.release: docker.stop docker.delete docker.build docker.run

#❓ help: @ Displays this message
help: SHELL:=/bin/bash
help:
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(firstword $(MAKEFILE_LIST))| tr -d '#'  | awk 'BEGIN {FS = ":.*?@ "}; {printf "${GREEN}%-30s${NOFORMAT} %s\n", $$1, $$2}'

#💻 lint: @ Formats code
lint: SHELL:=/bin/bash
lint: MIX_ENV=dev
lint:
	@mix format
	@mix check.credo

#💻 server: @ Starts a server with an interactive elixir shell.
server: SHELL:=/bin/bash
server:
	@iex -S mix phx.server

#📦 setup: @ Installs dependencies and set up database for dev and test envs
setup: SHELL:=/bin/bash
setup:
	MIX_ENV=dev mix setup
	MIX_ENV=test mix setup

#🧪 test: @ Runs all test suites
test: SHELL:=/bin/bash
test: MIX_ENV=test
test:
	@env -u PHX_SERVER mix test

#🧪 test.watch: @ Runs and watches all test suites
test.watch: SHELL:=/bin/bash
test.watch: MIX_ENV=test
test.watch:
	@echo "🧪👁️  Watching all test suites..."
	@mix test.watch

#🧪 test.wip.watch: @ Runs and watches test suites that match the wip tag
test.wip.watch: SHELL:=/bin/bash
test.wip.watch: MIX_ENV=test
test.wip.watch:
	@echo "🧪👁️  Watching test suites tagged with wip..."
	@mix test.watch --only wip

#📙 translations: @ Extract new untranslated phrases and merge translations to avaialble languages. This command uses fuzzy auto-generated transaltions, it generally needs a manual update to each language afterwards.
translations: SHELL:=/bin/bash
translations:
	@mix gettext.extract
	@mix gettext.merge priv/gettext --locale es_AR
	@mix gettext.merge priv/gettext --locale en

#♻️  backup.cache: @   Creates a backup of the redis cache
backup.cache: SHELL:=/bin/bash
backup.cache: BACKUP_NAME:=dump_`date +%d-%m-%Y"_"%H_%M_%S`
backup.cache:
	@docker run --rm --volumes-from dcomp_redis_service -v $(shell pwd)/backup/redis:/backup ubuntu tar cvf /backup/redis_${BACKUP_NAME}.tar /data

#♻️  backup.db: @   Creates a backup of the postgres db
backup.db: SHELL:=/bin/bash
backup.db: DB_USERNAME:=$(DB_USERNAME)
backup.db: BACKUP_NAME:=dump_`date +%d-%m-%Y"_"%H_%M_%S`.sql
backup.db:
	@docker exec -t dcomp_postgres_service pg_dumpall -c -U ${DB_USERNAME} > ./backup/postgres/postgres_${BACKUP_NAME}

#♻️  restore.cache: @   Restores a cache backup for the redis service
restore.cache: SHELL:=/bin/bash
restore.cache: BACKUP_NAME:=$(BACKUP_NAME)
restore.cache:
	@docker run --rm --volumes-from dcomp_redis_service -v $(pwd)/backup/redis:/backup ubuntu bash -c "cd /data && tar xvf /backup/backup.tar --strip 1"
	@docker compose restart redis

#♻️  restore.db: @   Restores a db backup for the postgres service
restore.db: SHELL:=/bin/bash
restore.db: DB_USERNAME:=${DB_USERNAME}
restore.db: DUMP_FILE:=$(DUMP_FILE)
restore.db:
	@cat backup/postgres/${DUMP_FILE} | docker exec -i dcomp_postgres_service psql -U ${DB_USERNAME}

#🐳 redis.cli: @ Starts a redis instance
redis.cli: SHELL:=/bin/bash
redis.cli: REDIS_PASS:=${REDIS_PASS}
redis.cli:
	@docker compose exec redis sh -c 'redis-cli -a ${REDIS_PASS}'

#🎁 sync.prod: @ Mirrors prod data (pg, redis) locally, wiping local data (ONLY=pg|redis, YES=1)
sync.prod:
	@${BINS_DIR}/sync_prod.sh

#🐳 start: @ Starts tilt services
start: SHELL:=/bin/bash
start:
	@echo Starting Tilt...
	@tilt up

#🐳 stop: @ Stop tilt services
stop:
	@echo Stopping Tilt...
	@tilt down

#🎁 redis.flush: @ Convenience funcion to flush redis keys in docker-compose deployments.
redis.flush: REDIS_PASS:=${REDIS_PASS}
redis.flush:
	@docker compose exec -e REDISCLI_AUTH=${REDIS_PASS} redis redis-cli FLUSHALL

#💻 connect.dev: @ Start dev a tmux session
connect.dev: SESSION:=dev
connect.dev: DEV_USER:=${DEV_USER}
connect.dev: DEV_HOST:=${DEV_HOST}
connect.dev:
	@${BINS_DIR}/tmux.sh ${SESSION}
