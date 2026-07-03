#!/bin/bash
set -e

GARAGE="docker exec garage-server /garage -c /etc/garage/garage.toml"

echo "==> Getting node ID..."
NODE_ID=$($GARAGE status 2>/dev/null | awk 'NR==3{print $1}')
if [[ -z "$NODE_ID" ]]; then
    echo "Error: could not determine node ID from garage status"
    exit 1
fi
echo "    Node ID: $NODE_ID"

echo "==> Assigning layout (zone=dc1, capacity=500MB)..."
$GARAGE layout assign "$NODE_ID" -z dc1 -c 500MB

echo "==> Applying layout..."
$GARAGE layout apply --version 1

echo "==> Waiting for cluster to be ready..."
while ! $GARAGE status 2>/dev/null | grep -qi "HEALTHY"; do
    sleep 2
    echo "    waiting..."
done

echo ""
echo "============================================"
echo " Garage cluster initialized."
echo "============================================"
echo ""
echo "Onboard a tenant with:"
echo "  ./scripts/garage-create-user.sh --name <name> --bucket <bucket> [--quota 500MB]"
