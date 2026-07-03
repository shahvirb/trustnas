# TrustNAS — Admin Guide

TrustNAS is a self-hosted NAS stack built on [Garage](https://garagehq.deuxfleurs.fr/) (S3-compatible distributed object storage) with [Tailscale](https://tailscale.com) for secure networking, nginx for bandwidth-limited reverse proxying, and [Homepage](https://gethomepage.dev) for a service dashboard.

## Architecture

```
┌─────────────────────────────────────────────┐
│ Tailscale mesh VPN (network namespace)       │
│                                              │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  │
│  │ homepage │  │  nginx   │  │  Garage  │  │
│  │  :3000   │  │  :80     │  │  :3900   │  │
│  │          │  │  :81     │  │  :3901   │  │
│  └──────────┘  └────┬─────┘  └──────────┘  │
│       │             │              │         │
│       │    ┌────────┴────────┐     │         │
│       │    │ reverse proxy   │     │         │
│       │    │ :80  → garage   │     │         │
│       │    │ :81  → garage   │     │         │
│       │    └─────────────────┘     │         │
└───────┼──────────────────────────────────────┘
        │
   Docker socket (read-only)
```

| Service | Purpose | Port |
|---------|---------|------|
| `garage` | S3 object storage engine (Garage v2.x) | 3900 (S3, 127.0.0.1 only); admin via docker exec RPC |
| `tailscale` | Secure mesh VPN | 8334 (HTTPS) |
| `nginx` | Bandwidth-limited S3 reverse proxy | 80 → garage, 81 → garage |
| `homepage` | Service dashboard | 3000 |
| `garage-init` | One-shot config generator | — |

## Prerequisites

- Docker and Docker Compose v2
- A Tailscale auth key ([generate one](https://login.tailscale.com/admin/settings/keys))

## Configuration

Copy `.env.example` to `.env` and configure:

| Variable | Default | Description |
|----------|---------|-------------|
| `TS_AUTHKEY` | (required) | Tailscale auth key |
| `GARAGE_RPC_SECRET` | (required) | Garage cluster secret — generate with `openssl rand -hex 32` |
| `NGINX_BANDWIDTH_LIMIT` | `6250k` | Per-connection bandwidth cap (~6.1 MB/s) |
| `NGINX_PUBLIC_PORT` | `63778` | Host port for nginx public S3 route (port 80) |
| `NGINX_GARAGE_PORT` | `63779` | Host port for nginx Garage route (port 81) |
| `TAILSCALE_HOSTNAME` | `trustnas` | Tailscale machine name |

### Paths

| Variable | Default | Description |
|----------|---------|-------------|
| `TAILSCALE_STATE_PATH` | `./docker-data/tailscale` | Tailscale state |
| `HOMEPAGE_LOGS_PATH` | `./docker-data/homepage/logs` | Homepage logs |
| `NGINX_LOGS_PATH` | `./docker-data/nginx_logs` | Nginx access/error logs |

Garage uses Docker-managed volumes (`garage-data`, `garage-config`) — no path variable needed.

## Deployment

```bash
cp .env.example .env
# edit .env with your values

docker compose pull
docker compose up -d
```

All services start automatically. Verify health:

```bash
# Garage (via RPC — no network exposure)
docker exec garage-server /garage -c /etc/garage/garage.toml json-api GetClusterHealth

# Nginx → Garage route
curl http://localhost:63779
# Should return XML AccessDenied (anonymous access is disabled)
```

## Garage Initialization

After first deploy, Garage needs cluster layout configuration:

```bash
./scripts/garage-init.sh
```

This script:
1. Detects the node ID
2. Assigns layout (`dc1` zone, single node, 500 MB capacity)
3. Applies the layout
4. Waits for the cluster to reach a healthy state

Once complete, Garage is ready to accept connections. Onboard your first tenant:

```bash
./scripts/garage-create-user.sh --name <name> --bucket <bucket>
```

Check node health:

```bash
docker exec garage-server /garage -c /etc/garage/garage.toml status
```

## Bucket Quotas

Garage v2.3+ supports per-bucket storage quotas, enforced automatically on upload.

### Set a quota

```bash
# Via the onboarding script (default 500MB):
./scripts/garage-create-user.sh --name alice --bucket alice-files
./scripts/garage-create-user.sh --name alice --bucket alice-files --quota 1G

# Manually via json-api (500 MB = 500000000 bytes):
docker exec garage-server /garage -c /etc/garage/garage.toml json-api UpdateBucket \
  '{"id":"<bucket-id>", "body":{"quotas":{"maxSize":500000000,"maxObjects":null}}}'

# Remove quota (unlimited):
docker exec garage-server /garage -c /etc/garage/garage.toml json-api UpdateBucket \
  '{"id":"<bucket-id>", "body":{"quotas":{"maxSize":null,"maxObjects":null}}}'
```

### View quota status

```bash
# Shows current size, object count, and quota status
docker exec garage-server /garage -c /etc/garage/garage.toml bucket info <bucket-name>

# Or via json-api for machine-readable output
docker exec garage-server /garage -c /etc/garage/garage.toml json-api GetBucketInfo '{"globalAlias":"<bucket>"}'
```

The output includes `quotas` (configured limits) and `stats` (current usage: `size` in bytes, `objects` count). Garage rejects uploads that would exceed the configured `maxSize`.

## Adding Tenants

Use the automated onboarding script:

```bash
./scripts/garage-create-user.sh --name alice --bucket alice-files
```

This script:
1. Creates a Garage access key named `alice`
2. Creates an S3 bucket `alice-files`
3. Grants the key read/write access to that bucket
4. Sets a 500MB storage quota on the bucket (configurable with `--quota`)
5. Prints credentials
6. Runs bandwidth benchmarks (direct and via nginx) as verification

Share the printed endpoint, key ID, secret key, bucket name, and region with the tenant.

## Manual Management

All Garage administration is done via CLI (`docker exec`):

### Keys

```bash
# List all keys
docker exec garage-server /garage -c /etc/garage/garage.toml key list

# Create a key
docker exec garage-server /garage -c /etc/garage/garage.toml key create <name>

# Delete a key
docker exec garage-server /garage -c /etc/garage/garage.toml key delete <name>

# Show key details
docker exec garage-server /garage -c /etc/garage/garage.toml key info <name>
```

### Buckets

```bash
# List buckets
docker exec garage-server /garage -c /etc/garage/garage.toml bucket list

# Create
docker exec garage-server /garage -c /etc/garage/garage.toml bucket create <name>

# Delete
docker exec garage-server /garage -c /etc/garage/garage.toml bucket delete <name>
```

### Access Control

Garage uses a per-key, per-bucket permission model:

```bash
# Grant read
docker exec garage-server /garage -c /etc/garage/garage.toml bucket allow --read <bucket> --key <key-name>

# Grant write
docker exec garage-server /garage -c /etc/garage/garage.toml bucket allow --write <bucket> --key <key-name>

# Grant both
docker exec garage-server /garage -c /etc/garage/garage.toml bucket allow --read --write <bucket> --key <key-name>

# Revoke all
docker exec garage-server /garage -c /etc/garage/garage.toml bucket deny --read --write <bucket> --key <key-name>

# Global key permissions (allow creating new buckets)
docker exec garage-server /garage -c /etc/garage/garage.toml key allow <key-name> --create-bucket
```

## Monitoring

### Garage

```bash
# Cluster status
docker exec garage-server /garage -c /etc/garage/garage.toml status

# Storage statistics
docker exec garage-server /garage -c /etc/garage/garage.toml stats

# Health check (RPC — no network exposure)
docker exec garage-server /garage -c /etc/garage/garage.toml json-api GetClusterHealth
```

### Nginx

```bash
# Access logs
docker logs p2p-nginx

# Error logs
docker exec p2p-nginx cat /var/log/nginx/error.log
```

### Container status

```bash
docker compose ps
```

## Bandwidth Limiting

Nginx enforces a per-connection rate limit via `limit_rate`. The default is `6250k` (~6.1 MB/s), set in `.env` as `NGINX_BANDWIDTH_LIMIT`.

Access via the nginx proxy (ports 63778 and 63779) is capped. Direct access to Garage (port 3900) is uncapped — useful for internal/admin operations that should bypass the limit.

To change the limit:
1. Set `NGINX_BANDWIDTH_LIMIT=<value>` in `.env` (e.g., `12500k` for ~12.2 MB/s)
2. Restart: `docker compose up -d nginx`

## Upgrading Garage

```bash
# Pull new image
docker compose pull garage

# Recreate (preserves volumes)
docker compose up -d garage
```

The `garage-init` container will regenerate the config from the template automatically.

When upgrading from v1.x to v2.x:
- `replication_mode` is replaced by `replication_factor` + `consistency_mode` in the config template.
- The admin API endpoints changed (prefix no longer used, e.g. `/health` instead of `/v1/health`).
- CLI commands for access control use positional arguments: `bucket allow --read --write <bucket> --key <key>`.
- See the full migration guide at https://garagehq.deuxfleurs.fr/documentation/working-documents/migration-2/

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `Error: No such file or directory` | Config not generated | `docker compose up -d garage-init` |
| `Invalid RPC secret key` | Secret too short | Generate with `openssl rand -hex 32` |
| `Ring not yet ready` | No layout applied | Run `scripts/garage-init.sh` |
| `capacity ... too small` | Capacity in wrong units | Use human-readable units (e.g., `500MB`, `1G`) |
| `Forbidden: Garage does not support anonymous access` | Expected — no anonymous S3 | Provide valid key/secret credentials |
| `replication_mode` not recognized | v2 config uses `replication_factor` | Update `garage.toml.template` to use `replication_factor = 1` |
