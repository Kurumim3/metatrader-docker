#!/usr/bin/env bash
# =============================================================================
# Automated Backup Routine with Retention Management
# =============================================================================
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
KEEP="${BACKUP_KEEP:-7}"
DEST="$ROOT/backups"; mkdir -p "$DEST"; chmod 750 "$DEST"
TS="$(date +%Y%m%d-%H%M%S)"
OUT="$DEST/mt-backup-$TS.tar.gz"
log() { echo "$(date '+%Y-%m-%dT%H:%M:%S%z') [$1] [backup] ${*:2}"; }

NEED="$(du -sm data 2>/dev/null | cut -f1 || echo 0)"
FREE="$(df -Pm "$DEST" | awk 'NR==2{print $4}')"
(( FREE > NEED / 2 )) || { log ERROR "Insufficient disk space for backup snapshot"; exit 1; }

TARGETS=()
[[ -d data/prefix-mt4/drive_c ]] && TARGETS+=(prefix-mt4/drive_c)
[[ -d data/prefix-mt5/drive_c ]] && TARGETS+=(prefix-mt5/drive_c)
if ((${#TARGETS[@]} == 0)); then
  log WARN "No Wine prefixes found; backup skipped"
  exit 0
fi

umask 077
log INFO "Creating backup archive: $OUT (${TARGETS[*]})"
rc=0
tar -C data -czf "$OUT" \
    --exclude='Tester' --exclude='tester' \
    --ignore-failed-read \
    "${TARGETS[@]}" 2>/dev/null || rc=$?
if (( rc == 1 )); then log WARN "Files changed during copy operation"; rc=0; fi
(( rc == 0 )) || { log ERROR "tar archive compression failed"; rm -f "$OUT"; exit "$rc"; }

chown 1000:1000 "$OUT" 2>/dev/null || true
chmod 600 "$OUT"
log INFO "Backup created: $(du -h "$OUT" | cut -f1)  $OUT"

# Rotate snapshots keeping only newest archives
ls -1t "$DEST"/mt-backup-*.tar.gz 2>/dev/null | tail -n +"$((KEEP + 1))" | while read -r old; do
  rm -f -- "$old"; log INFO "Removed outdated archive: $old"
done
