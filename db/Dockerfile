# syntax=docker/dockerfile:1
# =============================================================================
# bhorsha-db — PostgreSQL 16 with the Bhorsha schema v2 (13 tables, Architecture v3.1) and demo seed.
#
# The schema, seed and TypeORM baseline marker are baked into /docker-entrypoint-initdb.d, so every new
# container (empty volume) creates the tables and loads fresh, now()-relative
# demo data on first start. POSTGRES_PASSWORD is supplied at run time — never baked.
#
# Build context is ./db:   docker build -t bhorsha-db:dev ./db
# =============================================================================

ARG PG_IMAGE=postgres:16-alpine

# -----------------------------------------------------------------------------
# Stage 1 — build-time gate. Runs natively on the build machine ($BUILDPLATFORM),
# so multi-arch builds need no emulation. Fails the build if schema, seed,
# verify.sql or constraint-tests.sql fail.
# -----------------------------------------------------------------------------
FROM --platform=$BUILDPLATFORM ${PG_IMAGE} AS verify
USER postgres
COPY init/ /verify/init/
COPY scripts/ /verify/scripts/
COPY build-verify.sh /verify/build-verify.sh
RUN sh /verify/build-verify.sh && touch /tmp/verified

# -----------------------------------------------------------------------------
# Stage 2 — the published image (COPY-only, so it builds for any platform).
# -----------------------------------------------------------------------------
FROM ${PG_IMAGE}

ARG VERSION=dev
ARG REVISION=unknown
LABEL org.opencontainers.image.title="bhorsha-db" \
      org.opencontainers.image.description="PostgreSQL 16 with the Bhorsha ride-sharing schema v2 (13 tables) and demo seed data" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${REVISION}" \
      org.opencontainers.image.licenses="MIT"

# Depends on the verify stage, so the image cannot be built (or pushed) unless it passed.
COPY --from=verify /tmp/verified /usr/local/share/bhorsha/verified

COPY init/    /docker-entrypoint-initdb.d/
COPY scripts/ /scripts/

ENV POSTGRES_DB=bhorsha \
    POSTGRES_USER=bhorsha \
    TZ=UTC \
    PGTZ=UTC

# TCP check on purpose: during init Postgres listens on the socket only,
# so the container reports healthy only after schema + seed have loaded.
HEALTHCHECK --interval=5s --timeout=3s --start-period=10s --retries=20 \
  CMD pg_isready -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" || exit 1

CMD ["postgres", "-c", "log_min_duration_statement=250"]
