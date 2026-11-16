# Production image for the SMS gateway backend (a Mix release).
#
#   docker build -t sms-gateway ./backend
#
# Usually run through deploy/docker-compose.yml, which adds HTTPS (Caddy),
# a persistent volume for the SQLite database and the environment.
# Bump the versions below together; any Elixir >= 1.17 works.
ARG ELIXIR_IMAGE=elixir:1.18-otp-27-slim
ARG RUNNER_IMAGE=debian:bookworm-slim

FROM ${ELIXIR_IMAGE} AS builder

# build-essential: exqlite (SQLite) and circuits_uart compile native code
RUN apt-get update \
  && apt-get install -y --no-install-recommends build-essential git \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /app
ENV MIX_ENV=prod
RUN mix local.hex --force && mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV
RUN mkdir config
COPY config/config.exs config/prod.exs config/
RUN mix deps.compile

COPY priv priv
COPY lib lib
RUN mix compile

COPY config/runtime.exs config/
RUN mix release

FROM ${RUNNER_IMAGE}

# sqlite3 is for backups (deploy/backup.sh)
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    libstdc++6 openssl libncurses6 locales ca-certificates sqlite3 \
  && rm -rf /var/lib/apt/lists/* \
  && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

# dialout: access to a USB GSM modem when MODEM_ADAPTER=uart
RUN useradd --system --create-home --uid 1000 --groups dialout app \
  && mkdir -p /data && chown app /data

WORKDIR /app
COPY --from=builder --chown=app /app/_build/prod/rel/backend ./

USER app
# Migrations run automatically on boot
ENV MIX_ENV=prod PHX_SERVER=true PORT=4000 DATABASE_PATH=/data/gateway.db
VOLUME /data
EXPOSE 4000

CMD ["/app/bin/backend", "start"]
