# /// script
# requires-python = ">=3.13"
# dependencies = [
#     "boto3>=1.35",
#     "python-dotenv>=1.0",
# ]
# ///
import os
import sys
import time
from pathlib import Path

import boto3
from botocore.client import Config
from dotenv import find_dotenv, load_dotenv

load_dotenv(find_dotenv())

ENDPOINT = os.getenv("S3_ENDPOINT", "http://localhost:63778")
BUCKET = os.getenv("S3_BENCH_BUCKET", "test1")
ACCESS_KEY = os.environ["RUSTFS_ACCESS_KEY"]
SECRET_KEY = os.environ["RUSTFS_SECRET_KEY"]
REGION = os.getenv("S3_REGION", "us-east-1")

TEST_SIZES = [
    (5 * 1024 * 1024, "5 MB", "s3-bench-5mb.bin"),
    (50 * 1024 * 1024, "50 MB", "s3-bench-50mb.bin"),
]


def s3_client():
    return boto3.client(
        "s3",
        endpoint_url=ENDPOINT,
        aws_access_key_id=ACCESS_KEY,
        aws_secret_access_key=SECRET_KEY,
        region_name=REGION,
        config=Config(s3={"addressing_style": "path"}),
    )


def ensure_bucket(s3):
    existing = [b["Name"] for b in s3.list_buckets().get("Buckets", [])]
    if BUCKET in existing:
        print(f"Bucket '{BUCKET}' already exists.")
    else:
        s3.create_bucket(Bucket=BUCKET)
        print(f"Created bucket '{BUCKET}'.")


def generate_file(path: Path, size_bytes: int):
    chunk = bytes(os.urandom(min(1024 * 1024, size_bytes)))
    with open(path, "wb") as f:
        for _ in range(size_bytes // len(chunk)):
            f.write(chunk)
        remaining = size_bytes % len(chunk)
        if remaining:
            f.write(chunk[:remaining])


def upload_file(s3, path: Path, key: str):
    with open(path, "rb") as f:
        s3.put_object(Bucket=BUCKET, Key=key, Body=f)


def download_and_measure(s3, key: str, size_bytes: int):
    start = time.perf_counter()
    body = s3.get_object(Bucket=BUCKET, Key=key)["Body"]
    while body.read(1024 * 1024):
        pass
    elapsed = time.perf_counter() - start
    throughput = (size_bytes / (1024 * 1024)) / elapsed
    return elapsed, throughput


def cleanup_objects(s3, keys: list[str]):
    for key in keys:
        s3.delete_object(Bucket=BUCKET, Key=key)


def main():
    s3 = s3_client()
    ensure_bucket(s3)

    keys = [key for _, _, key in TEST_SIZES]
    cleanup_objects(s3, keys)
    print("Cleaned up any previous test files.\n")

    try:
        for size_bytes, label, key in TEST_SIZES:
            path = Path(f"/tmp/{key}")
            generate_file(path, size_bytes)
            upload_file(s3, path, key)
            path.unlink()
            print(f"{label:>6}  →  uploaded")

        print()

        for size_bytes, label, key in TEST_SIZES:
            elapsed, throughput = download_and_measure(s3, key, size_bytes)
            print(f"{label:>6}  →  download ok  {elapsed:.1f}s  {throughput:.2f} MB/s")

    finally:
        cleanup_objects(s3, keys)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\nAborted.", file=sys.stderr)
        sys.exit(1)
