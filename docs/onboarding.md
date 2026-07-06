# TrustNAS — User Guide

TrustNAS provides S3-compatible object storage backed by [Garage](https://garagehq.deuxfleurs.fr/), accessed securely via [Tailscale](https://tailscale.com). Your admin has created a bucket for you and will provide the credentials below.

## What You'll Receive

From your admin, you'll get:

| Item | Example |
|------|---------|
| **Endpoint (nginx)** | `http://localhost:63779` or `https://trustnas.tailc7008.ts.net:63779` |
| **Endpoint (direct)** | `http://localhost:3900` (default; may differ if admin changed `GARAGE_S3_PORT`) |
| **Region** | `garage` |
| **Bucket** | `alice-files` |
| **Key ID** | `GK...` |
| **Secret key** | `f586d055...` |

The nginx endpoint is bandwidth-limited (~6 MB/s). The direct endpoint is uncapped but may not be reachable depending on your network setup.


## Using Filestash (Web File Manager)

Filestash is an included web file manager with file previews, sharing, and
drag-and-drop uploads.

1. Open `http://trustnas.tailc7008.ts.net:8378` in your browser
2. Log in with:
   - **Username:** your Key ID
   - **Password:** your Secret Key
3. Your bucket appears — browse, upload, and manage files

## Bandwidth Limits

Traffic through the nginx proxy (port 63779) is capped at ~6 MB/s per connection. This ensures fair sharing between tenants. If you need higher throughput for bulk transfers, ask your admin about direct access (default port 3900, configurable via `GARAGE_S3_PORT`).

## Support

- Your bucket, credentials, and quota are managed by your TrustNAS admin
- For issues connecting, double-check the endpoint URL, key ID, and secret key
- The endpoint must be reachable — verify with `curl http://localhost:63779`
