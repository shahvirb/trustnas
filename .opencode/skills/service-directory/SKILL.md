---
name: service-directory
description: Generate docs/service-directory.md — a reference page listing every service, its URLs (hostname + Tailscale), port numbers, and descriptions. Use when the user asks for "service directory", "service list", "service map", or needs a quick reference of all exposed TrustNAS endpoints.
---

# Service Directory Generator

Generate `docs/service-directory.md` — a human-readable reference page listing every service in the TrustNAS stack with URLs for both local (hostname) and Tailscale access.

## Steps

### 1. Read the source files

- `docker-compose.yml` — services, ports, container names, network modes
- `nginx.conf.template` — listen ports, proxy_pass upstreams
- `.env` — read `TAILSCALE_HOSTNAME` (default: `trustnas` if absent or commented out)

### 2. Extract hostnames

- **Host hostname:** run `hostname` on the system
- **Tailnet hostname:** from `TAILSCALE_HOSTNAME` in `.env` (unset/commented-out defaults to `trustnas`)

These form the base of every URL:
- **Host URL:** `http(s)://<system-hostname>:<PORT>`
- **Tailnet URL:** `http(s)://<TAILSCALE_HOSTNAME>.<tailnet-name>:<PORT>`

If you cannot determine the tailnet name from env or config, show `<TAILSCALE_HOSTNAME>` in the Tailnet column and note that it is reachable at the host's Tailscale IP or MagicDNS name.

### 3. Determine Tailnet reachability

A port is reachable over the Tailnet **if and only if** it is published on the `tailscale` service in `docker-compose.yml`.

To determine this, parse the `ports:` section of the `tailscale` service and collect every host-side port. This set is the *Tailnet-reachable ports*. For every service port you encounter:

- **In the tailscale ports set** → Tailnet-reachable. Fill in the Tailnet URL column.
- **NOT in the tailscale ports set** → NOT Tailnet-reachable. Set the Tailnet URL column to `N/A`. If the port is bound to `127.0.0.1` or `::1`, use `N/A (internal)` instead.

Do **not** assume a port is Tailnet-reachable just because the service runs on the same host or shares a Docker network. The tailscale service's `ports:` is the single source of truth.

### 4. Parse nginx proxy routes

From `nginx.conf.template`, extract every `listen` directive and its corresponding `proxy_pass` upstream. These explain the indirect routes through which non-tailscale-namespace services are reached.

For any service reachable through an nginx proxy:
- The Tailnet URL uses the nginx `listen` port (which is published on the tailscale service), not the backend port.
- Include the proxy chain in the **Details** column (e.g., "nginx proxies to `filestash:8334`").

If nginx enforces `limit_rate`, note the bandwidth limit in Details or Notes.

### 5. Build the service tables

Cross-reference `docker-compose.yml` ports, nginx proxy routes, and network modes to produce the tables. Overwrite `docs/service-directory.md` with the result. Capitalize Tailscale exactly as "Tailscale".

The document must have the title `# Service Directory` followed by a brief intro sentence, then these sections:

#### Web UIs

A markdown table with columns: Service, Container, Host URL, Tailnet URL, Details.

Identify browser-facing HTTP services. Look for:
- Containers with `network_mode: "service:tailscale"` that serve HTTP on ports published by the tailscale service (e.g., homepage on 3000).
- Containers proxied by nginx that serve web interfaces (detected via nginx `proxy_pass` directives, e.g., filestash on 8334 proxied through port 8378, dozzle on 8080 proxied through port 8379).

For each, list the container name, published port, both URLs (using the reachability rule from Step 3), and a brief description of the service based on its image and role.

#### S3 Endpoints

A markdown table with columns: Endpoint, Container, Host URL, Tailnet URL, Details.

List every path through which the S3 API is reachable:
- **Nginx-proxied S3:** any nginx `proxy_pass` targeting `garage:3900`. The Tailnet URL uses the nginx listen port.
- **Direct S3:** the `garage-server` container's own published port (from `GARAGE_S3_PORT` or its default). This port is published on the garage container, not the tailscale container, so Tailnet URL = `N/A`.

If the nginx proxy enforces bandwidth limits, describe the distinction in the Details or Notes column.

#### Infrastructure

A markdown table with columns: Service, Container, Host URL, Tailnet URL, Details.

List services that are not end-user UIs or S3 endpoints. Include:
- **Tailscale HTTPS:** the port mapped to the tailscale container's web UI (e.g., 8334 → 8334).
- **Garage Admin API:** bound to `127.0.0.1` → Tailnet URL = `N/A`, accessible only via `docker exec`.
- **Garage RPC:** bound to `[::]` → Tailnet URL = `N/A`, internal cluster RPC.

Any other management/admin ports discovered during parsing that are bound to localhost or internal interfaces should also go here.

### 6. Add notes

At the bottom of the page, add a `## Notes` section. Derive notes from the parsed configuration:

- The Tailnet column uses `<TAILSCALE_HOSTNAME>`; adjust to your actual Tailscale MagicDNS name.
- For each port marked `N/A` in the Tailnet column, explain why — bound to localhost (internal only), not published on the tailscale service (host/LAN only), or internal cluster traffic.
- If nginx enforces `limit_rate`, note which endpoints are bandwidth-limited and which are uncapped. Direct (non-nginx) ports have no bandwidth limit.
- If multiple host ports map to the same nginx `listen` block, note they serve equivalent content.
- If a host/LAN-only service has an nginx proxy alternative reachable over Tailscale, point to the proxy port.

### 7. Write the file

Write or overwrite `docs/service-directory.md` with the generated content. Use consistent formatting: bold container names, inline code for ports, paths, and internal references (e.g., `garage:3900`). Host URL and Tailnet URL table cells must use bare URLs (no backticks) so they render as clickable links. Maintain proper markdown table alignment.
