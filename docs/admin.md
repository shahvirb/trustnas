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
│       │    │ :80  → rustfs   │     │         │
│       │    │ :81  → garage   │     │         │
│       │    └─────────────────┘     │         │
└───────┼──────────────────────────────────────┘
        │
   Docker socket (read-only)
```

| Service | Purpose | Port |
|---------|---------|------|
| `garage` | S3 object storage engine | 3900 (S3), 3901 (admin) |
| `tailscale` | Secure mesh VPN | 8334 (HTTPS) |
| `nginx` | Bandwidth-limited S3 reverse proxy | 80 → rustfs, 81 → garage |
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
| `RUSTFS_ACCESS_KEY` | `rustfsadmin` | RustFS admin access key |
| `RUSTFS_SECRET_KEY` | `changeme` | RustFS admin secret key |
| `GARAGE_RPC_SECRET` | (required) | Garage cluster secret — generate with `openssl rand -hex 32` |
| `NGINX_BANDWIDTH_LIMIT` | `6250k` | Per-connection bandwidth cap (~6.1 MB/s) |
| `NGINX_PUBLIC_PORT` | `63778` | Host port for nginx → RustFS route |
| `NGINX_GARAGE_PORT` | `63779` | Host port for nginx → Garage route |
| `TAILSCALE_HOSTNAME` | `trustnas` | Tailscale machine name |

### Paths

| Variable | Default | Description |
|----------|---------|-------------|
| `RUSTFS_DATA_PATH` | `./docker-data/rustfs` | RustFS persistent data |
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
# Garage
curl http://localhost:3901/v1/health

# Nginx → Garage route
curl http://localhost:63779
# Should return XML AccessDenied (anonymous access is disabled)

# Nginx → RustFS route
curl http://localhost:63778
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

## Adding Tenants

Use the automated onboarding script:

```bash
./scripts/garage-create-user.sh --name alice --bucket alice-files
```

This script:
1. Creates a Garage access key named `alice`
2. Creates an S3 bucket `alice-files`
3. Grants the key read/write access to that bucket
4. Prints credentials
5. Runs bandwidth benchmarks (direct and via nginx) as verification

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
docker exec garage-server /garage -c /etc/garage/garage.toml bucket allow <bucket> --key <key-name> --read

# Grant write
docker exec garage-server /garage -c /etc/garage/garage.toml bucket allow <bucket> --key <key-name> --write

# Grant both
docker exec garage-server /garage -c /etc/garage/garage.toml bucket allow <bucket> --key <key-name> --read --write

# Revoke all
docker exec garage-server /garage -c /etc/garage/garage.toml bucket deny <bucket> --key <key-name> --read --write

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

# Health endpoint
curl http://localhost:3901/v1/health
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

Access via the nginx proxy (ports 63778/63779) is capped. Direct access to Garage (port 3900) is uncapped — useful for internal/admin operations that should bypass the limit.

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

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `Error: No such file or directory` | Config not generated | `docker compose up -d garage-init` |
| `Invalid RPC secret key` | Secret too short | Generate with `openssl rand -hex 32` |
| `Ring not yet ready` | No layout applied | Run `scripts/garage-init.sh` |
| `capacity ... too small` | Capacity in wrong units | Use bytes (e.g., `524288000` for 500 MB) |
| `Forbidden: Garage does not support anonymous access` | Expected — no anonymous S3 | Provide valid key/secret credentials |
