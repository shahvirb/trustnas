#!/bin/bash
set -euo pipefail

usage() {
    cat <<EOF
Usage: $0 --name <key-name> --bucket <bucket-name> [--quota <size>]

Creates a Garage access key and bucket, grants read/write access,
sets a storage quota (default 500MB), then runs bandwidth benchmarks.

Example:
  $0 --name alice --bucket alice-files
  $0 --name alice --bucket alice-files --quota 1G
  $0 --name alice --bucket alice-files --quota 0   # unlimited
EOF
    exit 1
}

NAME=""
BUCKET=""
QUOTA="${GARAGE_DEFAULT_QUOTA:-500MB}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --name)   NAME="$2";   shift 2 ;;
        --bucket) BUCKET="$2"; shift 2 ;;
        --quota)  QUOTA="$2";  shift 2 ;;
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

parse_size() {
    local s="$1"
    s="${s// /}"
    local num=$(echo "$s" | sed 's/[^0-9.]//g')
    local unit=$(echo "$s" | sed 's/[0-9.]//g' | tr '[:lower:]' '[:upper:]')
    case "$unit" in
        B)   echo "${num%.*}" ;;
        K|KB) echo $((${num%.*} * 1000)) ;;
        KI|KIB) echo $((${num%.*} * 1024)) ;;
        M|MB) echo $((${num%.*} * 1000000)) ;;
        MI|MIB) echo $((${num%.*} * 1048576)) ;;
        G|GB) echo $((${num%.*} * 1000000000)) ;;
        GI|GIB) echo $((${num%.*} * 1073741824)) ;;
        T|TB) echo $((${num%.*} * 1000000000000)) ;;
        TI|TIB) echo $((${num%.*} * 1099511627776)) ;;
        *) echo "$num" ;;
    esac
}

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
$GARAGE bucket allow --read --write "$BUCKET" --key "$NAME" 2>&1 | grep -vE 'INFO|WARN' || true

if [[ "$QUOTA" != "0" ]]; then
    QUOTA_BYTES=$(parse_size "$QUOTA")
    echo "==> Setting quota: $QUOTA ($QUOTA_BYTES bytes)..."
    BUCKET_ID=$($GARAGE json-api GetBucketInfo "{\"globalAlias\":\"$BUCKET\"}" 2>/dev/null | grep -oP '"id"\s*:\s*"\K[^"]+')
    if [[ -z "$BUCKET_ID" ]]; then
        echo "Warning: could not resolve bucket UUID, skipping quota. Set it manually:"
        echo "  docker exec garage-server /garage json-api UpdateBucket '{\"id\":\"<bucket-id>\", \"body\":{\"quotas\":{\"maxSize\":$QUOTA_BYTES,\"maxObjects\":null}}}'"
    else
        $GARAGE json-api UpdateBucket "{\"id\":\"$BUCKET_ID\", \"body\":{\"quotas\":{\"maxSize\":$QUOTA_BYTES,\"maxObjects\":null}}}" 2>&1 | grep -vE 'INFO|WARN' || true
        echo "    Quota set successfully."
    fi
else
    echo "==> No quota (unlimited storage)."
fi

echo ""
echo "============================================"
echo " Tenant: $NAME"
echo "============================================"
echo " Endpoint (direct):  http://localhost:${GARAGE_S3_PORT:-3900}"
echo " Endpoint (nginx):   http://localhost:63779"
echo " Region:             garage"
echo " Bucket:             $BUCKET"
echo " Key ID:             $KEY_ID"
echo " Secret key:         $KEY_SECRET"
if [[ "$QUOTA" != "0" ]]; then
    echo " Quota:              $QUOTA"
fi
echo "============================================"

echo ""
echo "==> Running bandwidth benchmark (direct to Garage, port ${GARAGE_S3_PORT:-3900})..."
echo ""

S3_OUTPUT_DIRECT=$(mktemp)
S3_ACCESS_KEY="$KEY_ID" \
    S3_SECRET_KEY="$KEY_SECRET" \
    S3_ENDPOINT="http://localhost:${GARAGE_S3_PORT:-3900}" \
    S3_REGION="garage" \
    S3_BENCH_BUCKET="$BUCKET" \
    uv run "$PROJECT_DIR/scripts/s3_bench.py" 2>&1 | tee "$S3_OUTPUT_DIRECT"
echo ""

echo "==> Running bandwidth benchmark (via nginx, port 63779)..."
echo ""

S3_OUTPUT_NGINX=$(mktemp)
S3_ACCESS_KEY="$KEY_ID" \
    S3_SECRET_KEY="$KEY_SECRET" \
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
echo "  Endpoint:  http://localhost:63779  (or direct: http://localhost:${GARAGE_S3_PORT:-3900})"
echo "  Region:    garage"
echo "  Bucket:    $BUCKET"
echo "  Key ID:    $KEY_ID"
echo "  Secret:    $KEY_SECRET"
if [[ "$QUOTA" != "0" ]]; then
    echo "  Quota:     $QUOTA"
fi

rm -f "$S3_OUTPUT_DIRECT" "$S3_OUTPUT_NGINX"
