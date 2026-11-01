#!/usr/bin/env bash
set -euo pipefail

# 1. Idempotency Check
MARKER_FILE="/var/log/usms-db-bootstrap.done"
if [ -f "$MARKER_FILE" ]; then
    echo "Bootstrap marker $MARKER_FILE already exists. Exiting early."
    exit 0
fi

# 2. Install PostgreSQL & Create DB
dnf update -y
dnf install -y postgresql15-server postgresql15
postgresql-setup --initdb
systemctl enable --now postgresql

sudo -u postgres psql -c "CREATE DATABASE usms;" || true

# 3. Retrieve IMDSv2 Token and Instance ID
TOKEN=$(curl -s -S -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
INSTANCE_ID=$(curl -s -S -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id)
UTC_NOW=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# 4. Write Completion Marker File
cat << MARKER > "$MARKER_FILE"
InstanceID: $INSTANCE_ID
BootstrappedAt: $UTC_NOW
Status: COMPLETED
MARKER

echo "Database bootstrap completed successfully."
