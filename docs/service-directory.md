# Service Directory

A quick-reference guide to every service in the TrustNAS stack, with URLs for both hostname and Tailscale access.

## Web UIs

| Service | Container | Host URL | Tailnet URL | Details |
|---|---|---|---|---|
| Homepage | **homepage** | http://openmediavault:3000 | http://trustnas.tailc7008.ts.net:3000 | Service dashboard |
| Filestash | **filestash** | http://openmediavault:8378 | http://trustnas.tailc7008.ts.net:8378 | Web-based file manager (nginx proxies to `filestash:8334`) |
| Dozzle | **dozzle** | http://openmediavault:8379 | http://trustnas.tailc7008.ts.net:8379 | Real-time Docker container log viewer (nginx proxies to `dozzle:8080`) |
| S3 Browser | **p2p-nginx** | http://openmediavault:63778/s3ui | http://trustnas.tailc7008.ts.net:63778/s3ui | Client-side S3 bucket browser (nginx serves static files from `/usr/share/nginx/html/s3ui`) |
| Docs (mkdocs) | **mkdocs** | http://openmediavault:8000 | http://trustnas.tailc7008.ts.net:8000 | Live project documentation (mkdocs runs in tailscale network namespace, exposed directly on port 8000) |

## S3 Endpoints

| Endpoint | Container | Host URL | Tailnet URL | Details |
|---|---|---|---|---|
| S3 (bandwidth-limited) | **p2p-nginx** | http://openmediavault:63778 | http://trustnas.tailc7008.ts.net:63778 | Reverse proxy to `garage:3900` with per-connection rate limiting |
| S3 (direct, uncapped) | **garage-server** | http://openmediavault:3900 | http://trustnas.tailc7008.ts.net:3900 | Direct garage S3 API with no bandwidth limit |

## Infrastructure

| Service | Container | Host URL | Tailnet URL | Details |
|---|---|---|---|---|
| Tailscale HTTPS | **tailscale** | https://openmediavault:8334 | N/A | Tailscale web UI |
| Garage Admin API | **garage-server** | 127.0.0.1:3901 | N/A | Garage admin and health endpoints, only accessible via `docker exec garage-server /garage ...` |
| Garage RPC | **garage-server** | [::]:3902 | N/A | Internal cluster RPC, not directly user-facing |

## Notes

- The Tailnet column uses `trustnas.tailc7008.ts.net`; adjust to your actual Tailscale MagicDNS name if different.
- Garage Admin API and RPC are bound to localhost/Docker network and are not reachable over Tailscale or the host network — use `docker exec` or attach to the Docker network instead.
- S3 traffic through nginx (ports 63778, 63779) is bandwidth-limited by `NGINX_BANDWIDTH_LIMIT`; S3 through port 3900 is uncapped.
- Ports 63778 and 63779 are the same nginx instance; 63778 is the "public" route and 63779 is the "garage" route — both serve the same content unless the nginx config differentiates them.
