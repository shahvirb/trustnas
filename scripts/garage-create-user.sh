#!/bin/bash
set -euo pipefail

usage() {
    cat <<EOF
Usage: $0 --name <key-name> --bucket <bucket-name>

Creates a Garage access key and bucket, grants read/write access,
then runs bandwidth benchmarks to verify.

Example:
  $0 --name alice --bucket alice-files
EOF
    exit 1
}

NAME=""
BUCKET=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)   NAME="$2";   shift 2 ;;
        --bucket) BUCKET="$2"; shift 2 ;;
        *) usage ;;
    esac
done

[[ -z "$NAME" || -z "$BUCKET" ]] && usage

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
GARAGE="docker exec garage-server /garage -c /etc/garage/garage.toml"

if ! docker inspect garage-server --format '{{.State.Running}}' 2>/dev/null | grep -q true; then
    echo "Error: garage-server container is not running."
    echo "  Start it with: docker compose up -d garage"
    exit 1
fi

echo "==> Creating access key '$NAME'..."
KEY_OUTPUT=$($GARAGE key create "$NAME" 2>&1 | grep -vE 'INFO|WARN')
KEY_ID=$(echo "$KEY_OUTPUT" | grep "Key ID" | awk '{print $NF}')
KEY_SECRET=$(echo "$KEY_OUTPUT" | grep "Secret key" | awk '{print $NF}')

if [[ -z "$KEY_ID" || -z "$KEY_SECRET" ]]; then
    echo "Error: failed to parse key output:"
    echo "$KEY_OUTPUT"
    exit 1
fi
echo "    Key ID:     $KEY_ID"
echo "    Secret key: $KEY_SECRET"

echo "==> Creating bucket '$BUCKET'..."
$GARAGE bucket create "$BUCKET" 2>&1 | grep -vE 'INFO|WARN' || true

echo "==> Granting read/write access..."
$GARAGE bucket allow "$BUCKET" --key "$NAME" --read --write 2>&1 | grep -vE 'INFO|WARN' || true

echo ""
echo "============================================"
echo " Tenant: $NAME"
echo "============================================"
echo " Endpoint (direct):  http://localhost:3900"
echo " Endpoint (nginx):   http://localhost:63779"
echo " Region:             garage"
echo " Bucket:             $BUCKET"
echo " Key ID:             $KEY_ID"
echo " Secret key:         $KEY_SECRET"
echo "============================================"

echo ""
echo "==> Running bandwidth benchmark (direct to Garage, port 3900)..."
echo ""

S3_OUTPUT_DIRECT=$(mktemp)
RUSTFS_ACCESS_KEY="$KEY_ID" \
    RUSTFS_SECRET_KEY="$KEY_SECRET" \
    S3_ENDPOINT="http://localhost:3900" \
    S3_REGION="garage" \
    S3_BENCH_BUCKET="$BUCKET" \
    uv run "$PROJECT_DIR/scripts/s3_bench.py" 2>&1 | tee "$S3_OUTPUT_DIRECT"
echo ""

echo "==> Running bandwidth benchmark (via nginx, port 63779)..."
echo ""

S3_OUTPUT_NGINX=$(mktemp)
RUSTFS_ACCESS_KEY="$KEY_ID" \
    RUSTFS_SECRET_KEY="$KEY_SECRET" \
    S3_ENDPOINT="http://localhost:63779" \
    S3_REGION="garage" \
    S3_BENCH_BUCKET="$BUCKET" \
    uv run "$PROJECT_DIR/scripts/s3_bench.py" 2>&1 | tee "$S3_OUTPUT_NGINX"
echo ""

DIRECT_50MB=$(grep "50 MB" "$S3_OUTPUT_DIRECT" | grep -oP '[\d.]+(?= MB/s)')
NGINX_50MB=$(grep "50 MB" "$S3_OUTPUT_NGINX" | grep -oP '[\d.]+(?= MB/s)')

echo "============================================"
echo " Bandwidth comparison (50 MB download)"
echo "============================================"
printf " Direct:     %8s MB/s  (uncapped)\n" "${DIRECT_50MB:-N/A}"
printf " Via nginx:  %8s MB/s  (capped at 6250k)\n" "${NGINX_50MB:-N/A}"
echo "============================================"
echo ""
echo "Tenant '$NAME' is ready. Hand these credentials to the user:"
echo ""
echo "  Endpoint:  http://localhost:63779  (or direct: http://localhost:3900)"
echo "  Region:    garage"
echo "  Bucket:    $BUCKET"
echo "  Key ID:    $KEY_ID"
echo "  Secret:    $KEY_SECRET"

rm -f "$S3_OUTPUT_DIRECT" "$S3_OUTPUT_NGINX"
