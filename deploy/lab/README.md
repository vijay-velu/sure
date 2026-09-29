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
docker compose --profile backup up -d backup   # optional: pg_dump every 24h → ./backups
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
docker compose exec web /lab/load-secrets.sh bin/rails runner 'puts ActiveRecordEncryptionConfig.explicitly_configured?'   # true
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
| Build context includes `deploy/` — a `docker build` from the repo root would copy `secrets/`, `.env` and backups into image layers | `/deploy/` excluded in `.dockerignore` (verified: canary secret absent from the image) |
| Backup container `apk add`s pg/rclone on every start (needs internet, unpinned at runtime) | `pg_dump` from the `postgres:16` image, internal network only, uid 1000, no capabilities |

## Backups and restore

The `backup` profile runs `pg_dump` from the `postgres:16` image every `BACKUP_INTERVAL_HOURS`
(24) into `./backups` (directory 700, files 600, owned by uid 1000), keeping `BACKUP_KEEP_DAYS` (7).
It installs nothing at start and has no internet access; copy `./backups` off the host with your
own tooling.

**Back up `./secrets` too, separately.** Provider credentials (e.g. the SimpleFIN access URL) are
encrypted with the Active Record keys in there; a database dump restored without them keeps
everything except those credentials, which you would re-link.

Restore into an empty database:

```bash
docker compose stop web worker
gunzip -c backups/sure-<stamp>.sql.gz | docker compose exec -T db psql -U sure -d sure_production -v ON_ERROR_STOP=1
docker compose start web worker
```

## Running Rails commands

`docker compose exec` bypasses the entrypoint, so the secrets are not loaded. Prefix commands
with the shim, e.g. `docker compose exec web /lab/load-secrets.sh bin/rails console`.

## Known limits

- **What was run for real** (sandbox, 2026-09-29): this compose file with generated secrets, on an
  image built like the upstream Dockerfile minus apt packages (libvips, poppler, jemalloc — image
  variants and PDF parsing untested). Verified: all services healthy, no host ports, db has no
  egress while the worker has it, capabilities dropped as listed, secrets absent from
  `docker inspect`, Active Record encryption on, `web` reachable over the `proxy` network, and a
  backup restored into a fresh database with identical data.
- **Not run here**: the upstream Dockerfile build itself (Debian mirrors blocked in the sandbox),
  TLS at your reverse proxy, and OIDC against your IdP — check `docker compose logs web` on first run.
- Rails does not restrict the `Host` header in production; rely on your proxy to only forward `APP_HOST`.
- The domain allowlist trusts the IdP's `email` claim — make sure your IdP only issues verified emails.
