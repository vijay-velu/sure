#!/bin/sh
# Export Docker secrets as environment variables, then hand off to Sure's entrypoint.
# /run/secrets/secret_key_base -> SECRET_KEY_BASE, etc. Sure reads these only from ENV.
set -eu
if [ -d /run/secrets ]; then
  for f in /run/secrets/*; do
    [ -f "$f" ] || continue
    name=$(basename "$f" | tr '[:lower:]-' '[:upper:]_')
    export "$name=$(cat "$f")"
  done
fi
exec /rails/bin/docker-entrypoint "$@"
