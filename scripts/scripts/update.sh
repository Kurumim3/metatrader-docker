#!/usr/bin/env bash
# =============================================================================
# Container Rebuild & Application Update Script
# =============================================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

log() { echo "$(date '+%Y-%m-%dT%H:%M:%S%z') [$1] [update] ${*:2}"; }

log INFO "Creating pre-update backup snapshot..."
"$ROOT/scripts/backup.sh"

log INFO "Rebuilding container image with latest layers..."
docker compose build --pull
docker compose up -d

log INFO "Update and deployment completed successfully"
