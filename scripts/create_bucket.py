# /// script
# requires-python = ">=3.13"
# dependencies = [
#     "boto3>=1.35",
#     "requests>=2.31",
# ]
# ///
import argparse
import hashlib
import json
import os
import secrets
import string
import sys

import boto3
import requests
from botocore.auth import SigV4Auth
from botocore.awsrequest import AWSRequest
from botocore.client import Config
from botocore.credentials import Credentials

DEFAULT_ENDPOINT = "http://rustfs-server:9000"
DEFAULT_REGION = "us-east-1"
DEFAULT_ADMIN_ACCESS_KEY = os.environ["RUSTFS_ACCESS_KEY"]
DEFAULT_ADMIN_SECRET_KEY = os.environ["RUSTFS_SECRET_KEY"]


def s3_client(endpoint: str, region: str) -> boto3.client:
    return boto3.client(
        "s3",
        endpoint_url=endpoint,
        aws_access_key_id=DEFAULT_ADMIN_ACCESS_KEY,
        aws_secret_access_key=DEFAULT_ADMIN_SECRET_KEY,
        region_name=region,
        config=Config(s3={"addressing_style": "path"}),
    )


def sign_request(
    method: str,
    url: str,
    data: str | None = None,
    region: str = DEFAULT_REGION,
    access_key: str = DEFAULT_ADMIN_ACCESS_KEY,
    secret_key: str = DEFAULT_ADMIN_SECRET_KEY,
) -> AWSRequest:
    request = AWSRequest(method=method, url=url, data=data)
    payload = data.encode("utf-8") if data else b""
    request.headers["x-amz-content-sha256"] = hashlib.sha256(payload).hexdigest()
    credentials = Credentials(access_key, secret_key)
    SigV4Auth(credentials, "s3", region).add_auth(request)
    return request


def admin_request(
    method: str,
    path: str,
    params: dict[str, str] | None = None,
    data: str | None = None,
    endpoint: str = DEFAULT_ENDPOINT,
    region: str = DEFAULT_REGION,
    access_key: str = DEFAULT_ADMIN_ACCESS_KEY,
    secret_key: str = DEFAULT_ADMIN_SECRET_KEY,
) -> requests.Response:
    from urllib.parse import urlencode

    url = f"{endpoint}{path}"
    if params:
        url += "?" + urlencode(params)

    signed = sign_request(method, url, data, region, access_key, secret_key)
    headers = dict(signed.headers)
    resp = requests.request(method, url, headers=headers, data=signed.body)
    if resp.status_code >= 400:
        print(f"Error ({resp.status_code}): {resp.text}", file=sys.stderr)
        sys.exit(1)
    return resp


def create_bucket(endpoint: str, bucket: str, region: str) -> None:
    s3 = s3_client(endpoint, region)
    s3.create_bucket(Bucket=bucket)
    print(f"Created bucket '{bucket}'.")


def set_bucket_quota(
    endpoint: str,
    bucket: str,
    quota_bytes: int,
    region: str,
    access_key: str,
    secret_key: str,
) -> None:
    admin_request(
        "PUT",
        "/minio/admin/v3/set-bucket-quota",
        params={
            "bucket": bucket,
            "limit": str(quota_bytes),
            "quotaType": "hard",
        },
        endpoint=endpoint,
        region=region,
        access_key=access_key,
        secret_key=secret_key,
    )
    print(f"Set quota of {quota_bytes} bytes on bucket '{bucket}'.")


def put_bucket_policy(
    endpoint: str,
    bucket: str,
    username: str,
    region: str,
) -> None:
    policy = {
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Deny",
                "Principal": "*",
                "Action": "s3:*",
                "Resource": [
                    f"arn:aws:s3:::{bucket}",
                    f"arn:aws:s3:::{bucket}/*",
                ],
                "Condition": {
                    "StringNotEquals": {"aws:username": username}
                },
            },
            {
                "Effect": "Allow",
                "Principal": {"AWS": [f"arn:aws:iam:::user/{username}"]},
                "Action": "s3:*",
                "Resource": [
                    f"arn:aws:s3:::{bucket}",
                    f"arn:aws:s3:::{bucket}/*",
                ],
            },
        ],
    }
    s3 = s3_client(endpoint, region)
    s3.put_bucket_policy(Bucket=bucket, Policy=json.dumps(policy))
    print(f"Set bucket policy on '{bucket}' restricting access to user '{username}'.")


def generate_password(length: int = 20) -> str:
    chars = string.ascii_letters + string.digits
    return "".join(secrets.choice(chars) for _ in range(length))


def parse_quota(value: str) -> int:
    value = value.strip().upper()
    units: dict[str, int] = {
        "TIB": 1024**4,
        "GIB": 1024**3,
        "MIB": 1024**2,
        "KIB": 1024,
        "TB": 1000**4,
        "GB": 1000**3,
        "MB": 1000**2,
        "KB": 1000,
        "B": 1,
    }
    for unit, multiplier in sorted(units.items(), key=lambda x: -len(x[0])):
        if value.endswith(unit):
            num = float(value[: -len(unit)])
            return int(num * multiplier)
    return int(value)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create a RustFS bucket with quota and a single restricted IAM user"
    )
    parser.add_argument("--bucket", required=True, help="Bucket name")
    parser.add_argument(
        "--quota", required=True, help="Quota (e.g. 10GiB, 500MB, 1TB)"
    )
    parser.add_argument("--username", required=True, help="IAM username to create")
    parser.add_argument(
        "--endpoint",
        default=DEFAULT_ENDPOINT,
        help=f"RustFS S3/admin endpoint (default: {DEFAULT_ENDPOINT})",
    )
    parser.add_argument(
        "--region",
        default=DEFAULT_REGION,
        help=f"AWS region (default: {DEFAULT_REGION})",
    )
    parser.add_argument(
        "--admin-access-key",
        default=DEFAULT_ADMIN_ACCESS_KEY,
        help="Admin access key for privileged operations",
    )
    parser.add_argument(
        "--admin-secret-key",
        default=DEFAULT_ADMIN_SECRET_KEY,
        help="Admin secret key for privileged operations",
    )
    args = parser.parse_args()

    quota_bytes = parse_quota(args.quota)
    password = generate_password()

    create_bucket(args.endpoint, args.bucket, args.region)
    set_bucket_quota(
        args.endpoint,
        args.bucket,
        quota_bytes,
        args.region,
        args.admin_access_key,
        args.admin_secret_key,
    )
    put_bucket_policy(args.endpoint, args.bucket, args.username, args.region)

    print()
    print("\u2500" * 50)
    print("Bucket created successfully!")
    print("\u2500" * 50)
    print(f"  Bucket:      {args.bucket}")
    print(f"  Quota:       {args.quota} ({quota_bytes} bytes)")
    print(f"  Endpoint:    {args.endpoint}")
    print()
    print(f"  Username:    {args.username}")
    print(f"  Password:    {password}")
    print()
    print("Create the IAM user in the RustFS console:")
    print("  http://localhost:9001 -> Users -> Add User")
    print()
    print("The bucket policy is already in place --")
    print(f"once the user '{args.username}' exists, only they")
    print(f"can access bucket '{args.bucket}'.")
    print("\u2500" * 50)


if __name__ == "__main__":
    main()
