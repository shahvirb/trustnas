#!/bin/bash
set -e

GARAGE="docker exec garage-server /garage -c /etc/garage/garage.toml"

echo "==> Getting node ID..."
NODE_ID=$($GARAGE node id | cut -d'@' -f1)
echo "    Node ID: $NODE_ID"

echo "==> Assigning layout (zone=dc1, capacity=500MB)..."
$GARAGE layout assign "$NODE_ID" -z dc1 -c 524288000

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
echo "  ./scripts/garage-create-user.sh --name <name> --bucket <bucket>"
