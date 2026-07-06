# Service Directory

Reference of all services in the TrustNAS stack, with URLs for local (hostname) and Tailscale access.

## Web UIs

| Service | Container | Host URL | Tailnet URL | Details |
|---------|-----------|----------|-------------|---------|
| Homepage | `homepage` | http://openmediavault:3000 | http://trustnas.tailc7008.ts.net:3000 | Dashboard UI; shares tailscale network namespace |
| Filestash | `filestash` | http://openmediavault:8378 | http://trustnas.tailc7008.ts.net:8378 | Web file manager; nginx on port `8378` proxies to `filestash:8334`; bandwidth limited |
| Dozzle | `dozzle` | http://openmediavault:8379 | http://trustnas.tailc7008.ts.net:8379 | Docker log viewer; shares tailscale network namespace; no bandwidth limit |
| MkDocs | `mkdocs` | http://openmediavault:8000 | http://trustnas.tailc7008.ts.net:8000 | Documentation server (MkDocs Material); shares tailscale network namespace |

## S3 Endpoints

| Endpoint | Container | Host URL | Tailnet URL | Details |
|----------|-----------|----------|-------------|---------|
| Garage S3 (nginx) | `p2p-nginx` | http://openmediavault:63779 | http://trustnas.tailc7008.ts.net:63779 | nginx proxies to `garage:3900`; bandwidth limited to 6250k |
| Garage S3 (direct) | `garage-server` | http://openmediavault:3900 | N/A | Direct S3 API on `garage:3900`; no bandwidth limit; host/LAN only |

## Infrastructure

| Service | Container | Host URL | Tailnet URL | Details |
|---------|-----------|----------|-------------|---------|
| Tailscale HTTPS | `tailscale` | http://openmediavault:8334 | http://trustnas.tailc7008.ts.net:8334 | Tailscale Funnel/Serve HTTPS port |
| Garage Admin API | `garage-server` | http://127.0.0.1:3901 | N/A | Bound to `127.0.0.1`; internal only, accessible via `docker exec garage-server` |
| Garage RPC | `garage-server` | N/A | N/A | Bound to `[::]:3902`; internal cluster RPC only |

## Notes

- The Tailnet column uses `trustnas.tailc7008.ts.net` (tailnet `tailc7008.ts.net`). Adjust `trustnas` if you override `TAILSCALE_HOSTNAME` in `.env`.

- **N/A (not Tailnet-reachable):**
  - Port `3900` (Garage S3 direct): Not published on the `tailscale` service. Use `63779` to reach S3 over the Tailnet instead.
  - Port `3901` (Garage Admin): Bound to `127.0.0.1` — internal only, accessible via `docker exec garage-server`.
  - Port `3902` (Garage RPC): Internal cluster communication only.

- **Bandwidth limits:** nginx enforces `limit_rate 6250k` on proxied endpoints — Filestash (`8378`) and Garage S3 via nginx (`63779`). Direct Garage S3 on port `3900` and Dozzle (`8379`) have no bandwidth limit.

- Port `63779` (NGINX_GARAGE_PORT) maps to nginx which proxies to `garage:3900`.
