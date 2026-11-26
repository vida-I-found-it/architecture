#!/bin/sh
# Runs once, when the postgres container starts on an empty data dir (docker-entrypoint-initdb.d).
# 1) provision-roles.sql as admin; 2) each service's schema.sql CONNECTED AS ITS OWN ROLE (never as admin).
# The scripts come read-only from docs/data/scripts (single source of truth).
set -eu

: "${CORE_DB_PASSWORD:?CORE_DB_PASSWORD is required}"
: "${SCHEDULE_DB_PASSWORD:?SCHEDULE_DB_PASSWORD is required}"
# auth and notify have no running service yet: throwaway random passwords, never printed.
rand() { head -c 18 /dev/urandom | od -An -tx1 | tr -d ' \n'; }

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  -v auth_pw="$(rand)" -v core_pw="$CORE_DB_PASSWORD" \
  -v schedule_pw="$SCHEDULE_DB_PASSWORD" -v notify_pw="$(rand)" \
  -f /sql/provision-roles.sql

# Local socket during init: trust auth, so no password travels in a command line.
psql -v ON_ERROR_STOP=1 --username core_service --dbname "$POSTGRES_DB" -f /sql/core/schema.sql
psql -v ON_ERROR_STOP=1 --username schedule_service --dbname "$POSTGRES_DB" -f /sql/schedule/schema.sql
