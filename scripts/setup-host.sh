#!/usr/bin/env bash
# =============================================================================
# Host Setup & Resource Optimization Script
# =============================================================================
set -euo pipefail
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$APP_DIR/.env"

log() { echo "$(date '+%Y-%m-%dT%H:%M:%S%z') [$1] [setup-host] ${*:2}"; }
die() { log ERROR "$*"; exit 1; }

[[ $EUID -eq 0 ]] || die "Root permissions required: run with sudo $0"
command -v docker >/dev/null 2>&1 || die "Docker is not installed on the system"
docker compose version >/dev/null 2>&1 || die "Docker Compose v2 is required"

# Evaluate physical resources
TOTAL_MB="$(awk '/^MemTotal:/{print int($2/1024)}' /proc/meminfo)"
SWAP_MB="$(awk '/^SwapTotal:/{print int($2/1024)}' /proc/meminfo)"
CORES="$(nproc)"

if   (( TOTAL_MB <= 2048 )); then SWAP_TARGET=2048
elif (( TOTAL_MB <= 4096 )); then SWAP_TARGET=1024
else SWAP_TARGET=0; fi

log INFO "Host resources detected: RAM=${TOTAL_MB}MB swap=${SWAP_MB}MB cpus=${CORES}"

# Provision swapfile if needed
make_swapfile() {
  local mb="$1"
  rm -f /swapfile
  fallocate -l "${mb}M" /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count="$mb" status=none
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
}

if (( SWAP_TARGET > 0 && SWAP_MB < SWAP_TARGET - 100 )); then
  NEED=$(( SWAP_TARGET - SWAP_MB ))
  log INFO "Configuring ${NEED}MB swapfile"
  [[ -f /swapfile ]] || make_swapfile "$NEED"
  if ! swapon /swapfile 2>/dev/null; then
    make_swapfile "$NEED"
    swapon /swapfile 2>/dev/null || log WARN "swapon failed (OpenVZ/LXC container detected?)"
  fi
  grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  SWAP_MB="$(awk '/^SwapTotal:/{print int($2/1024)}' /proc/meminfo)"
fi

# Apply kernel virtual memory tunings
cat > /etc/sysctl.d/99-mt-docker.conf <<'SYS'
vm.swappiness=20
vm.vfs_cache_pressure=50
SYS
sysctl -q -p /etc/sysctl.d/99-mt-docker.conf >/dev/null 2>&1 || log WARN "Unable to apply sysctl rules directly"

# Compute container headroom
RESERVE=$(( TOTAL_MB * 15 / 100 )); (( RESERVE >= 200 )) || RESERVE=200
MEM_MB=$(( TOTAL_MB - RESERVE ))
(( MEM_MB >= 600 )) || log WARN "Only ${MEM_MB}MB available for the container runtime"
SWAP_ALLOW=$(( SWAP_MB > 2048 ? 2048 : SWAP_MB ))
if (( SWAP_ALLOW == 0 )); then
  SWAP_ALLOW=512
  log WARN "Host without active swap; setting memswap_limit with +512MB headroom"
fi
MEMSWAP_MB=$(( MEM_MB + SWAP_ALLOW ))
SHM=$(( TOTAL_MB <= 2048 ? 128 : 512 ))
CPUS="$(awk -v n="$CORES" 'BEGIN{ if (n<=1) print "1.0"; else printf "%.1f", n-0.5 }')"

# Directory creation and secure permissions
mkdir -p "$APP_DIR"/data/{prefix-mt4,prefix-mt5,logs,installers} "$APP_DIR/backups"
chown -R 1000:1000 "$APP_DIR/data" "$APP_DIR/backups"
chmod 700 "$APP_DIR"/data/prefix-mt4 "$APP_DIR"/data/prefix-mt5
chmod 750 "$APP_DIR"/data/logs "$APP_DIR"/data/installers "$APP_DIR/backups"
chmod 755 "$APP_DIR"/scripts/*.sh

touch "$ENV_FILE"; chmod 600 "$ENV_FILE"
if [[ -n "${SUDO_USER:-}" ]]; then
  chown "$SUDO_USER:" "$ENV_FILE" 2>/dev/null || true
elif [[ -d "$APP_DIR" ]]; then
  OWNER="$(stat -c %U "$APP_DIR" 2>/dev/null || true)"
  [[ -n "$OWNER" && "$OWNER" != "root" ]] && chown "$OWNER:" "$ENV_FILE" 2>/dev/null || true
fi

get_kv()     { grep -E "^$1=" "$ENV_FILE" | head -n1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//' || true; }
set_kv()     { if grep -qE "^$1=" "$ENV_FILE"; then sed -i "s|^$1=.*|$1=$2|" "$ENV_FILE"; else echo "$1=$2" >> "$ENV_FILE"; fi; }
default_kv() { grep -qE "^$1=" "$ENV_FILE" || echo "$1=$2" >> "$ENV_FILE"; }

default_kv MEM_LIMIT "${MEM_MB}m"
default_kv MEMSWAP_LIMIT "${MEMSWAP_MB}m"
default_kv CPUS "$CPUS"
default_kv SHM_SIZE "${SHM}m"
default_kv PIDS_LIMIT 1024
default_kv IMAGE_NAME "mt-trader:local"
default_kv CONTAINER_NAME "mt"
default_kv TZ "America/Sao_Paulo"
default_kv BIND_ADDR "127.0.0.1"
default_kv NOVNC_PORT "6080"
default_kv RESOLUTION "1024x600x16"
default_kv EA_DEPS_MT4 '"corefonts vcrun2019 winhttp gdiplus msxml6"'
default_kv EA_DEPS_MT5 '"corefonts vcrun2019 winhttp gdiplus msxml6"'
default_kv MT4_ARCH "win32"

if [[ -z "$(get_kv VNC_PASSWORD)" ]]; then
  PW="$(head -c 24 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | cut -c1-8)"
  set_kv VNC_PASSWORD "$PW"
  log INFO "Generated random VNC password: $PW"
else
  log INFO "Retaining existing VNC password"
fi

if [[ -n "${SUDO_USER:-}" ]]; then
  chown "$SUDO_USER:" "$ENV_FILE" 2>/dev/null || true
fi

log INFO "Runtime limits configured: mem=${MEM_MB}m memswap=${MEMSWAP_MB}m cpus=${CPUS} shm=${SHM}m"
log INFO "Host preparation completed"
