# ==============================================================================
# Build Stage
# ==============================================================================
FROM hexpm/elixir:1.15.7-erlang-26.2.1-alpine-3.18.4 AS builder

# Install build dependencies
RUN apk add --no-cache build-base git openssl-dev

WORKDIR /app

# Set build environment
ENV MIX_ENV=prod

# Install hex and rebar
RUN mix local.hex --force && mix local.rebar --force

# Copy dependency files
COPY mix.exs ./
COPY mix.lock* ./
COPY config config

# Fetch and compile dependencies
RUN mix deps.get --only prod
RUN mix deps.compile

# Copy source code
COPY lib lib
RUN mkdir -p priv

# Compile and build release
RUN mix compile
RUN mix release call_service

# ==============================================================================
# Runtime Stage
# ==============================================================================
FROM alpine:3.18.4 AS runtime
RUN apk add --no-cache libstdc++ openssl ncurses-libs curl tini

RUN addgroup -g 1000 -S appgroup && \
    adduser -u 1000 -S appuser -G appgroup

WORKDIR /app
COPY --from=builder /app/_build/prod/rel/call_service ./
RUN chown -R appuser:appgroup /app

USER appuser
EXPOSE 4002 4369

HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost:4002/health || exit 1

ENV MIX_ENV=prod LANG=C.UTF-8 PHX_SERVER=true
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["bin/call_service", "start"]
