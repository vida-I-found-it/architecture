#!/bin/sh
# Writes .env next to compose.yaml with throwaway test values, generated on the fly.
# Never overwrites an existing .env and never prints the values. .env is git-ignored.
set -eu

cd "$(dirname "$0")"
if [ -e .env ]; then
  echo ".env already exists: delete it yourself if you want new values" >&2
  exit 1
fi

pw() { openssl rand -hex 16; }
umask 077
cat > .env <<EOF
POSTGRES_ADMIN_PASSWORD=$(pw)
CORE_DB_PASSWORD=$(pw)
SCHEDULE_DB_PASSWORD=$(pw)
MONGO_ROOT_PASSWORD=$(pw)
SCHEDULE_MONGO_PASSWORD=$(pw)
FIXED_USER_ID=$(uuidgen | tr 'A-Z' 'a-z')
EOF
echo ".env written (mode 600)"
