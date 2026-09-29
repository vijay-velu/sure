# Sure — hardened home-lab stack

Builds this fork from source and runs it behind your own TLS + SSO reverse proxy.
Nothing is published on host ports; Postgres and Redis have no route out.

## Bring-up

```bash
cd deploy/lab
./gen-secrets.sh                      # random secrets in ./secrets (mode 600); never overwrites
sudo sh -c "printf '%s' 'YOUR_OIDC_CLIENT_SECRET' > secrets/oidc_client_secret"
cp .env.example .env && $EDITOR .env  # APP_HOST, OIDC_*, ALLOWED_OIDC_DOMAINS (required)
docker network create proxy 2>/dev/null || true
docker compose up -d --build
docker compose --profile backup up -d backup   # optional nightly pg_dump → ./backups
```

Point your reverse proxy at `web:3000` on the `proxy` network. It must send `X-Forwarded-Proto: https`.

### Bootstrap your admin (one time)

JIT provisioning defaults to `link_only` (SSO never creates users). For your first login:

```bash
echo 'AUTH_JIT_MODE=create_and_link' >> .env && docker compose up -d web
# sign in via SSO once, then:
sed -i '/^AUTH_JIT_MODE=/d' .env && docker compose up -d web
```

Once SSO works, set `AUTH_LOCAL_LOGIN_ENABLED=false` for SSO-only login.

### Coming from Actual Budget

See [MIGRATING_FROM_ACTUAL.md](MIGRATING_FROM_ACTUAL.md): export, import with opening balances and
paired transfers, then SimpleFIN directly into Sure with a safe overlap.

SimpleFIN runs in the `worker` container (it needs the `egress` network). Its access URL is a
bearer credential for every linked bank account; with the Active Record encryption keys above it
is stored encrypted at rest.

## Checks

```bash
docker compose ps                                                     # web healthy
docker compose exec web curl -fsS http://127.0.0.1:3000/up            # 200
docker ps --filter name=sure-lab --format '{{.Names}} {{.Ports}}'     # no 0.0.0.0 mappings
docker compose exec db bash -c 'timeout 3 bash -c "</dev/tcp/1.1.1.1/443" && echo EGRESS || echo no-egress'  # no-egress
docker inspect sure-lab-web-1 --format '{{.HostConfig.CapDrop}} {{.HostConfig.SecurityOpt}}'
docker compose exec web bin/rails runner 'puts ActiveRecordEncryptionConfig.explicitly_configured?'   # true
```

## What's hardened vs upstream `compose.example.yml`

| Upstream | Here |
|---|---|
| Public fallback `SECRET_KEY_BASE` baked into the file (session forgery if not overridden) | Random per install, Docker secret |
| Default DB password `sure_password` | Random, Docker secret (`POSTGRES_PASSWORD_FILE`) |
| Active Record encryption off unless configured → provider tokens/bank payloads in plaintext | Keys set → encrypted at rest |
| Port 3000 published on all interfaces | No host ports; `proxy` network only |
| Empty `ALLOWED_OIDC_DOMAINS` = anyone at the IdP self-provisions | Required; JIT `link_only` by default |
| Signup page open | `ONBOARDING_STATE=closed` |
| DNS pinned to 8.8.8.8 / 1.1.1.1 | Host resolver (your lab DNS) |
| Full capabilities | `cap_drop: ALL`, `no-new-privileges`, mem/pid limits |

## Known limits

- **Not runtime-tested in CI here**: the stack was validated with `docker compose config`, but the image could not be
  built in the authoring sandbox (Debian mirrors blocked). First run on your host is the real test — check `docker compose logs web`.
- Rails does not restrict the `Host` header in production; rely on your proxy to only forward `APP_HOST`.
- The domain allowlist trusts the IdP's `email` claim — make sure your IdP only issues verified emails.
- Backups land on the same host; add an rclone remote (`BACKUP_DESTINATION`) for off-host copies.
