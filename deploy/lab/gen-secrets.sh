#!/bin/sh
# Create ./secrets with fresh random values (never overwrites existing files).
set -eu
cd "$(dirname "$0")"
umask 077
mkdir -p secrets
gen() { [ -s "secrets/$1" ] || openssl rand -hex "$2" | tr -d '\n' > "secrets/$1"; }
gen secret_key_base 64
gen postgres_password 24
gen active_record_encryption_primary_key 32
gen active_record_encryption_deterministic_key 32
gen active_record_encryption_key_derivation_salt 32
[ -e secrets/oidc_client_secret ] || : > secrets/oidc_client_secret
# Sure runs as uid 1000 and compose file-secrets keep host ownership, so hand them to that uid.
if chown 1000:1000 secrets/* 2>/dev/null; then chmod 400 secrets/*; else
  echo "WARN: could not chown secrets to uid 1000; run: sudo chown 1000:1000 secrets/* && sudo chmod 400 secrets/*"
fi
ls -ln secrets
echo "Next: put your IdP client secret in secrets/oidc_client_secret (as root: it is read-only for uid 1000)."
