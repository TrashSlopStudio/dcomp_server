# Find eligible builder and runner images on Docker Hub. We use Ubuntu/Debian instead of
# Alpine to avoid DNS resolution issues in production.
#
# https://hub.docker.com/r/hexpm/elixir/tags?page=1&name=ubuntu
# https://hub.docker.com/_/ubuntu?tab=tags
#
#
# This file is based on these images:
#
#   - https://hub.docker.com/r/hexpm/elixir/tags - for the build image
#   - https://hub.docker.com/_/debian?tab=tags&page=1&name=bookworm-20260610-slim - for the release image
#   - https://pkgs.org/ - resource for finding needed packages
#   - Ex: hexpm/elixir:1.20.1-erlang-29.0.2-debian-bookworm-20260610
#
# Note: bullseye (Debian 11) was previously used here, but its LTS security
# support has ended and its packages have been pruned from security.debian.org,
# which broke `apt-get install` in the release stage. Bumped to bookworm
# (Debian 12), with the builder and
# runner pinned to the same dated snapshot so their glibc versions match.
ARG BUILDER_IMAGE="hexpm/elixir:1.20.1-erlang-29.0.2-debian-bookworm-20260610"
ARG RUNNER_IMAGE="debian:bookworm-20260610-slim"
FROM ${BUILDER_IMAGE} AS builder

# install build dependencies
RUN apt-get update -y && apt-get install -y build-essential git curl && \
    apt-get clean && rm -f /var/lib/apt/lists/*_*

# prepare build dir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# set build ENV
ENV MIX_ENV=prod

# install mix dependencies
COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# copy compile-time config files before we compile dependencies
# to ensure any relevant config change will trigger the dependencies
# to be re-compiled.
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

# download the tailwind/esbuild binaries once; cached until their versions change
RUN mix tailwind.install && mix esbuild.install

# Compile the release
COPY priv priv
COPY lib lib

RUN mix compile

# Note: if your project uses a tool like https://purgecss.com/,
# which customizes asset compilation based on what it finds in
# your Elixir templates, you will need to move the asset compilation
# step down so that `lib` is available.
COPY assets assets

# Compile assets (same steps as `mix assets.deploy`)
RUN mix tailwind dcomp --minify && \
    mix esbuild dcomp --minify && \
    mix phx.digest

# Changes to config/runtime.exs don't require recompiling the code
COPY config/runtime.exs config/

RUN mix release

# start a new build stage so that the final image will only contain
# the compiled release and other runtime necessities
FROM ${RUNNER_IMAGE}

ARG DATABASE_URL

RUN apt-get update -y && apt-get install -y libstdc++6 openssl libncurses5 locales \
  && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Set the locale
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8

WORKDIR /opt/app
COPY devops/builder/entrypoint.sh .
RUN chmod +x entrypoint.sh
RUN chown nobody /opt/app

# Only copy the final release from the build stage
COPY --from=builder --chown=nobody:root app/_build/prod/rel/dcomp .

USER nobody

CMD ["/opt/app/entrypoint.sh", "start"]
