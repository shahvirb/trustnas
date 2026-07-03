# TrustNAS — User Guide

TrustNAS provides S3-compatible object storage backed by [Garage](https://garagehq.deuxfleurs.fr/), accessed securely via [Tailscale](https://tailscale.com). Your admin has created a bucket for you and will provide the credentials below.

## What You'll Receive

From your admin, you'll get:

| Item | Example |
|------|---------|
| **Endpoint (nginx)** | `http://localhost:63779` or `https://trustnas:63779` |
| **Endpoint (direct)** | `http://localhost:3900` |
| **Region** | `garage` |
| **Bucket** | `alice-files` |
| **Key ID** | `GK...` |
| **Secret key** | `f586d055...` |

The nginx endpoint is bandwidth-limited (~6 MB/s). The direct endpoint is uncapped but may not be reachable depending on your network setup.

## Connecting with AWS CLI

Install the [AWS CLI](https://aws.amazon.com/cli/) and configure:

```bash
aws configure set aws_access_key_id     GK...
aws configure set aws_secret_access_key f586...
aws configure set region                garage
```

Then use `--endpoint` for all commands:

```bash
# List your buckets
aws s3 ls --endpoint http://localhost:63779

# List objects in your bucket
aws s3 ls s3://alice-files --endpoint http://localhost:63779

# Upload a file
aws s3 cp document.pdf s3://alice-files/ --endpoint http://localhost:63779

# Download a file
aws s3 cp s3://alice-files/document.pdf . --endpoint http://localhost:63779

# Delete a file
aws s3 rm s3://alice-files/document.pdf --endpoint http://localhost:63779
```

## Connecting with Python (boto3)

```bash
pip install boto3
```

```python
import boto3
from botocore.client import Config

s3 = boto3.client(
    "s3",
    endpoint_url="http://localhost:63779",
    aws_access_key_id="GK...",
    aws_secret_access_key="f586...",
    region_name="garage",
    config=Config(s3={"addressing_style": "path"}),
)

# List objects
for obj in s3.list_objects(Bucket="alice-files").get("Contents", []):
    print(obj["Key"])

# Upload
s3.put_object(Bucket="alice-files", Key="hello.txt", Body=b"Hello, TrustNAS!")

# Download
resp = s3.get_object(Bucket="alice-files", Key="hello.txt")
print(resp["Body"].read().decode())
```

## Using the S3 Browser

TrustNAS includes a web-based S3 browser at `/s3ui`:

1. Open `http://localhost:63778/s3ui` in your browser
2. Enter your credentials:
   - **Endpoint:** `http://localhost:63779`
   - **Access Key:** your Key ID
   - **Secret Key:** your secret key
   - **Region:** `garage`
3. Click **Connect**

You can now browse, upload, and download files from your bucket.

## Connecting with rclone

[rclone](https://rclone.org/) is a powerful command-line tool for managing cloud storage:

```bash
rclone config
# n) New remote
# name> trustnas
# s) S3 Compliant
# provider> Other
# env_auth> false
# access_key_id> GK...
# secret_access_key> f586...
# region> garage
# endpoint> http://localhost:63779
# acl> (leave blank)
# Edit advanced config? n)
```

```bash
# List buckets
rclone lsd trustnas:

# List files
rclone ls trustnas:alice-files

# Copy local directory to bucket
rclone copy ./my-files trustnas:alice-files/

# Sync local directory with bucket
rclone sync ./my-files trustnas:alice-files/
```

## Connecting with Cyberduck

[Cyberduck](https://cyberduck.io/) is a graphical S3 client for macOS and Windows:

1. Open Cyberduck → **Open Connection**
2. Select **Amazon S3** from the dropdown
3. Enter:
   - **Server:** `localhost`
   - **Port:** `63779`
   - **Access Key ID:** your Key ID
   - **Secret Access Key:** your secret key
4. Click **Connect**

## Bandwidth Limits

Traffic through the nginx proxy (port 63779) is capped at ~6 MB/s per connection. This ensures fair sharing between tenants. If you need higher throughput for bulk transfers, ask your admin about direct access on port 3900.

## Support

- Your bucket, credentials, and quota are managed by your TrustNAS admin
- For issues connecting, double-check the endpoint URL, key ID, and secret key
- The endpoint must be reachable — verify with `curl http://localhost:63779`
