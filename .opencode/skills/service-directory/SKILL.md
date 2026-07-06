---
name: service-directory
description: Generate docs/service-directory.md — a reference page listing every service, its URLs (hostname + Tailscale), port numbers, and descriptions. Use when the user asks for "service directory", "service list", "service map", or needs a quick reference of all exposed TrustNAS endpoints.
---

# Service Directory Generator

Generate `docs/service-directory.md` — a human-readable reference page listing every service in the TrustNAS stack with URLs for both local (hostname) and Tailscale access.

## Steps

### 1. Read the source files

Read these files:
- `docker-compose.yml` — services, ports, container names, network modes
- `nginx.conf.template` — listen ports, proxy_pass upstreams, location blocks
- `.env` — read `TAILSCALE_HOSTNAME` (default: `trustnas` if absent or env does not exist)
- `.env.example` — fallback for any env var that is unset or missing in `.env`

### 2. Extract the hostnames

Get the **Host URL hostname** by running `hostname` on the system. Get the **Tailnet hostname** from `TAILSCALE_HOSTNAME` in `.env` (unset/commented-out defaults to `trustnas`).

The two addresses for every URL are:
- **Host:** `http(s)://<system-hostname>:<PORT>` (e.g., `http://openmediavault:3000`)
- **Tailnet:** `http(s)://<TAILSCALE_HOSTNAME>.<tailnet-name>:<PORT>` (e.g., `http://trustnas.your-tailnet.ts.net:3000`)

If you cannot determine the tailnet name from the env or config, show `<TAILSCALE_HOSTNAME>` alone for the Tailnet column and note that it is reachable at the host's Tailscale IP or MagicDNS name.

### 3. Build the service table

Cross-reference `docker-compose.yml` ports with `nginx.conf.template` routes to produce the table. Overwrite `docs/service-directory.md` with the result. Capitalize Tailscale exactly as "Tailscale".

The document must have the title `# Service Directory` followed by a brief intro sentence, then these sections:

#### Web UIs

A markdown table with columns: Service, Container, Host URL, Tailnet URL, Details.

For each web UI service:
- **Homepage**: container `homepage`, port 3000 — Service dashboard
- **Filestash**: container `filestash`, port 8378 — Web-based file manager (nginx proxies to filestash:8334)
- **Dozzle**: container `dozzle`, port 8379 — Real-time Docker container log viewer (nginx proxies to dozzle:8080)
- **S3 Browser**: container `p2p-nginx`, path `/s3ui` on port 63778 or 63779 — Client-side S3 bucket browser (nginx serves static files from `/usr/share/nginx/html/s3ui`)
- **Docs (mkdocs)**: container `mkdocs`, port 8000 — Live project documentation (mkdocs runs in tailscale network namespace, exposed directly on port 8000)

#### S3 Endpoints

A markdown table with columns: Endpoint, Container, Host URL, Tailnet URL, Details.

- **S3 (bandwidth-limited)**: container `p2p-nginx`, ports 63778 and 63779 — Reverse proxy to garage:3900 with per-connection rate limiting
- **S3 (direct, uncapped)**: container `garage-server`, port 3900 — Direct garage S3 API with no bandwidth limit

#### Infrastructure

A markdown table with columns: Service, Container, Host URL, Tailnet URL, Details.

- **Tailscale HTTPS**: container `tailscale`, port 8334 — Tailscale web UI
- **Garage Admin API**: container `garage-server`, bound to `127.0.0.1:3901` — Garage admin and health endpoints, only accessible via `docker exec garage-server /garage ...`
- **Garage RPC**: container `garage-server`, bound to `[::]:3902` — Internal cluster RPC, not directly user-facing

### 4. Add disclaimers

At the bottom of the page, add a `## Notes` section with these bullets:
- The Tailnet column uses `<TAILSCALE_HOSTNAME>`; adjust to your actual Tailscale MagicDNS name (e.g., `trustnas.your-tailnet.ts.net`).
- Garage Admin API and RPC are bound to localhost/Docker network and are not reachable over Tailscale or the host network — use `docker exec` or attach to the Docker network instead.
- S3 traffic through nginx (ports 63778, 63779) is bandwidth-limited by `NGINX_BANDWIDTH_LIMIT`; S3 through port 3900 is uncapped.
- Ports 63778 and 63779 are the same nginx instance; 63778 is the "public" route and 63779 is the "garage" route — both serve the same content unless the nginx config differentiates them.

### 5. Write the file

Write or overwrite `docs/service-directory.md` with the generated content. Use consistent formatting: bold container names, inline code for ports, paths, and internal references (e.g. `garage:3900`). Host URL and Tailnet URL table cells must use bare URLs (no backticks) so they render as clickable links. Maintain proper markdown table alignment.
