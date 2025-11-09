# Build stage
FROM elixir:1.15-alpine AS build

# Install build dependencies
RUN apk add --update git build-base nodejs npm

RUN mkdir /app
WORKDIR /app

# Install Hex + Rebar
RUN mix do local.hex --force, local.rebar --force

# Set build ENV
ENV MIX_ENV=prod

# Install mix dependencies
COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile

# Build assets
COPY assets assets
COPY priv priv
RUN mix assets.deploy

# Build project
COPY lib lib
RUN mix compile

# Build release
RUN mix release

# App stage
FROM alpine:3.18 AS app

# Install runtime dependencies
RUN apk add --update bash openssl postgresql-client libstdc++ libgcc ncurses-libs

EXPOSE 4000
ENV MIX_ENV=prod

# Prepare app directory
RUN mkdir /app
WORKDIR /app

# Copy release to app container
COPY --from=build /app/_build/prod/rel/blitzkeys .
COPY entrypoint.sh .
RUN chmod +x /app/entrypoint.sh
RUN chown -R nobody: /app
USER nobody

ENV HOME=/app
CMD ["bash", "/app/entrypoint.sh"]
