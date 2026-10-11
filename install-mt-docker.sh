#!/usr/bin/env bash
# =============================================================================
# install-mt-docker.sh — Installer + Manager for MT4/MT5 in Docker with noVNC
# =============================================================================
# Interactive menu for Ubuntu/Debian VPS without a graphical interface (1–2 GB RAM).
# Uses the OFFICIAL MetaQuotes installers (no broker configuration required).
#
# Usage:
#   sudo bash install-mt-docker.sh            # open the menu
#   sudo bash install-mt-docker.sh guided    # full guided installation
#   sudo bash install-mt-docker.sh status    # status / diagnostics
#   sudo bash install-mt-docker.sh backup    # backup now
#
# After the first run, the shortcut  sudo mt-menu  becomes available.
#
# Configuration (optional):
#   Copy .env.example to .env if you want to customize. The script loads .env
#   automatically if it exists in $APP_DIR or next to the script.
#
#   APP_DIR=/opt/mt-docker   base directory
#   SSH_PORT=22              VPS SSH port (for access messages)
#   WINE_VERSION=...         Wine version; default 10.0.0.0~jammy-1
#
# Robots/Indicators (folder "robos" created NEXT TO the script on first run):
#   MT4/Experts  MT4/Indicators  (.ex4 / .mq4)
#   MT5/Experts  MT5/Indicators  (.ex5 / .mq5)
#   sets/                        (.set for both MT4 and MT5; the menu asks which terminal)
#   Place the files in the correct folder and use menu option 3.
#
# NOTE — Line endings (CRLF): if the file came from Windows, run first:
#     sed -i 's/\r$//' install-mt-docker.sh
# =============================================================================
set -uo pipefail
# (no "set -e" in the menu: an error in one step returns to the menu instead of
#  closing everything. Generated scripts inside the container use set -e normally.)

# -----------------------------------------------------------------------------
# Global configuration
# -----------------------------------------------------------------------------
APP_DIR="${APP_DIR:-/opt/mt-docker}"

# Load .env (if present) BEFORE reading the other variables.
# Precedence: command-line variables > .env > defaults.
_load_env_file() {
  local f
  for f in "${ENV_FILE_OVERRIDE:-}" "$APP_DIR/.env" "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "$0")")/.env"; do
    [[ -n "$f" && -r "$f" ]] || continue
    # shellcheck disable=SC1090
    set -a; . "$f"; set +a
    return 0
  done
}
_load_env_file

COMPOSE_FILE="$APP_DIR/docker-compose.yml"
ENV_FILE="$APP_DIR/.env"
MENU_BIN="/usr/local/bin/mt-menu"

SELF="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SELF")" && pwd)"

# "robos" and "backups" folders: stay NEXT TO where the script was run (easy to find)
# and are remembered in $APP_DIR/.robos_dir so the "mt-menu" shortcut uses the same path.
# To change location: set ROBOS_DIR=/path and/or BACKUP_DIR=/path when running the script.
resolver_robos_dir() {
  local salvo=""
  if [[ -z "${ROBOS_DIR:-}" ]]; then
    [[ -f "$APP_DIR/.robos_dir" ]] && salvo="$(<"$APP_DIR/.robos_dir")"
    if [[ -n "$salvo" ]]; then
      ROBOS_DIR="$salvo"
    elif [[ "$SCRIPT_DIR" == "$APP_DIR"/* ]]; then
      ROBOS_DIR="$APP_DIR/robos"
    else
      ROBOS_DIR="$SCRIPT_DIR/robos"
    fi
  fi
  # backups: same place (next to the robots folder), remembered in .backup_dir
  if [[ -z "${BACKUP_DIR:-}" ]]; then
    local sb=""
    [[ -f "$APP_DIR/.backup_dir" ]] && sb="$(<"$APP_DIR/.backup_dir")"
    BACKUP_DIR="${sb:-$(dirname "$ROBOS_DIR")/backups}"
  fi
  if mkdir -p "$APP_DIR" 2>/dev/null; then
    printf '%s\n' "$ROBOS_DIR" > "$APP_DIR/.robos_dir" 2>/dev/null || true
    printf '%s\n' "$BACKUP_DIR" > "$APP_DIR/.backup_dir" 2>/dev/null || true
  fi
}
resolver_robos_dir

# -----------------------------------------------------------------------------
# Visual (plain terminal; falls back to ASCII if locale is not UTF-8)
# -----------------------------------------------------------------------------
if [[ -t 1 ]]; then
  C_RED=$'\033[0;31m'; C_GREEN=$'\033[0;32m'; C_YELLOW=$'\033[1;33m'
  C_BLUE=$'\033[0;34m'; C_CYAN=$'\033[0;36m'; C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'; C_RESET=$'\033[0m'
else
  C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_CYAN=""; C_BOLD=""; C_DIM=""; C_RESET=""
fi

if [[ "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" =~ [Uu][Tt][Ff]-?8 ]]; then
  S_OK="✓"; S_ERR="✗"; S_WARN="⚠"; S_INFO="ℹ"; S_DOT="●"; S_ARR="›"; S_LINE="─"
  SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
else
  S_OK="+"; S_ERR="x"; S_WARN="!"; S_INFO="i"; S_DOT="*"; S_ARR=">"; S_LINE="-"
  SPIN=('|' '/' '-' '\')
fi

COLS="$(tput cols 2>/dev/null || echo 70)"
[[ "$COLS" =~ ^[0-9]+$ ]] || COLS=70
(( COLS > 78 )) && COLS=78
(( COLS < 50 )) && COLS=50

rule() {
  local n="${1:-$COLS}" i out=""
  for ((i = 0; i < n; i++)); do out+="$S_LINE"; done
  printf '%s%s%s\n' "$C_DIM" "$out" "$C_RESET"
}

log()  { echo "$(date '+%Y-%m-%dT%H:%M:%S%z') [$1] ${*:2}" >&2; }
die()  { echo "${C_RED}${S_ERR}${C_RESET}  $*" >&2; exit 1; }
info() { echo "${C_BLUE}${S_INFO}${C_RESET}  $*"; }
ok()   { echo "${C_GREEN}${S_OK}${C_RESET}  $*"; }
warn() { echo "${C_YELLOW}${S_WARN}${C_RESET}  $*"; }
err()  { echo "${C_RED}${S_ERR}${C_RESET}  $*" >&2; }

title() {
  clear 2>/dev/null || true
  echo
  echo "  ${C_BOLD}${C_CYAN}$1${C_RESET}"
  rule
  echo
}

badge() { # badge ok|warn|err|off "text"
  local c
  case "$1" in
    ok)   c="$C_GREEN" ;;
    warn) c="$C_YELLOW" ;;
    err)  c="$C_RED" ;;
    *)    c="$C_DIM" ;;
  esac
  printf '%s%s%s %s' "$c" "$S_DOT" "$C_RESET" "$2"
}

require_root() {
  [[ $EUID -eq 0 ]] || die "run as root: sudo bash $SELF"
}

pause() {
  echo
  read -rp "  ${C_DIM}ENTER to go back...${C_RESET} " _ || true
}

confirm() {
  local ans
  read -rp "  $1 [y/N] " ans || true
  ans="${ans,,}"
  [[ "$ans" == "y" || "$ans" == "yes" || "$ans" == "s" || "$ans" == "sim" ]]
}

# Ctrl+C does not close the menu: it only interrupts the current task
trap 'echo' INT
trap 'tput cnorm 2>/dev/null || true' EXIT

# Run a command in the background showing a spinner, elapsed time and the last log line.
# usage: run_spin "message" /path/to/log command args...
run_spin() {
  local msg="$1" logf="$2"; shift 2
  mkdir -p "$(dirname "$logf")" 2>/dev/null || true
  : > "$logf"
  "$@" >"$logf" 2>&1 &
  local pid=$! start=$SECONDS i=0 el last
  trap 'kill "$pid" 2>/dev/null; tput cnorm 2>/dev/null' INT
  if [[ -t 1 ]]; then
    tput civis 2>/dev/null || true
    while kill -0 "$pid" 2>/dev/null; do
      el=$((SECONDS - start))
      last="$(tail -n1 "$logf" 2>/dev/null | tr -d '\r' | tr -cd '[:print:]' | cut -c1-$((COLS - ${#msg} - 16)))"
      printf '\r\033[K  %s%s%s %s %s[%02d:%02d]%s %s%s%s' \
        "$C_CYAN" "${SPIN[i % ${#SPIN[@]}]}" "$C_RESET" "$msg" \
        "$C_DIM" $((el / 60)) $((el % 60)) "$C_RESET" "$C_DIM" "$last" "$C_RESET"
      i=$((i + 1))
      sleep 0.2
    done
    printf '\r\033[K'
    tput cnorm 2>/dev/null || true
  else
    info "$msg ..."
  fi
  local rc=0
  wait "$pid" || rc=$?
  trap 'echo' INT
  el=$((SECONDS - start))
  if (( rc == 0 )); then
    ok "$msg ${C_DIM}($((el / 60))m$((el % 60))s)${C_RESET}"
  else
    err "$msg failed (code $rc). Last log lines:"
    tail -n 15 "$logf" 2>/dev/null | sed 's/^/      /' >&2
    echo "      ${C_DIM}full log: $logf${C_RESET}" >&2
  fi
  return "$rc"
}

# -----------------------------------------------------------------------------
# Utilities
# -----------------------------------------------------------------------------
detect_ssh_port() {
  local p
  if [[ -n "${SSH_PORT:-}" ]]; then printf '%s' "$SSH_PORT"; return; fi
  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    p="$(echo "$SSH_CONNECTION" | awk '{print $4}')"
    [[ "$p" =~ ^[0-9]+$ ]] && { printf '%s' "$p"; return; }
  fi
  if command -v sshd >/dev/null 2>&1; then
    p="$(sshd -T 2>/dev/null | awk '/^port /{print $2; exit}')"
    [[ "$p" =~ ^[0-9]+$ ]] && { printf '%s' "$p"; return; }
  fi
  printf '22'
}
SSH_PORT="$(detect_ssh_port)"

server_ip() {
  local ip=""
  ip="$(curl -4fsS --max-time 4 https://ifconfig.me 2>/dev/null || true)"
  [[ "$ip" =~ ^[0-9.]+$ ]] || ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  printf '%s' "${ip:-VPS_IP}"
}

env_get() { # env_get KEY
  [[ -f "$ENV_FILE" ]] || return 0
  grep -E "^$1=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//'
}

env_set() { # env_set KEY VALUE  (safe for any character)
  local k="$1" v="$2" tmp
  tmp="$(mktemp)"
  { grep -v "^${k}=" "$ENV_FILE" 2>/dev/null || true; } > "$tmp"
  printf '%s=%s\n' "$k" "$v" >> "$tmp"
  cat "$tmp" > "$ENV_FILE"
  rm -f "$tmp"
}

container_name() {
  local n; n="$(env_get CONTAINER_NAME)"
  printf '%s' "${n:-mt}"
}

dc() { docker compose -f "$COMPOSE_FILE" "$@"; }

container_running() {
  [[ -f "$COMPOSE_FILE" ]] || return 1
  dc ps -q --status running 2>/dev/null | grep -q .
}

need_base() {
  if [[ ! -f "$COMPOSE_FILE" ]]; then
    err "Base not installed yet. Use option 1 (or A) first."
    return 1
  fi
}

# Wait until the container's supervisord socket exists
wait_supervisor() {
  local i
  for i in $(seq 1 30); do
    dc exec -T mt test -S /tmp/supervisor.sock >/dev/null 2>&1 && return 0
    sleep 2
  done
  return 1
}

wait_healthy() {
  local cn st="unknown" i
  cn="$(container_name)"
  for i in $(seq 1 36); do
    st="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$cn" 2>/dev/null || echo missing)"
    [[ "$st" == "healthy" ]] && return 0
    printf '\r  %s waiting for healthcheck... %s (%ds)  ' "${SPIN[i % ${#SPIN[@]}]}" "$st" $((i * 5))
    sleep 5
  done
  printf '\r\033[K'
  return 1
}

# Terminal state for the dashboard
term_state() { # term_state mt4|mt5
  local id="$1" marker="$APP_DIR/data/prefix-${1}/.mt_exe_path"
  if [[ ! -s "$marker" ]]; then
    badge off "${id^^} not installed"; return
  fi
  if container_running; then
    local line
    line="$(dc exec -T mt mt-sv status "$id" 2>/dev/null | head -1 || true)"
    case "$line" in
      *RUNNING*)  badge ok  "${id^^} running" ;;
      *STARTING*) badge warn "${id^^} starting" ;;
      *)          badge err "${id^^} stopped" ;;
    esac
  else
    badge off "${id^^} installed (container stopped)"
  fi
}

painel() {
  local d c mem
  if command -v docker >/dev/null 2>&1; then d="$(badge ok "Docker")"; else d="$(badge off "Docker missing")"; fi
  if [[ ! -f "$COMPOSE_FILE" ]]; then
    c="$(badge off "base not installed")"
  elif container_running; then
    local st; st="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$(container_name)" 2>/dev/null || echo ?)"
    case "$st" in
      healthy)  c="$(badge ok "container healthy")" ;;
      starting) c="$(badge warn "container starting")" ;;
      *)        c="$(badge warn "container: $st")" ;;
    esac
  else
    c="$(badge err "container stopped")"
  fi
  mem="$(awk '/^MemTotal:/{t=$2}/^MemAvailable:/{a=$2}END{printf "%d/%d MB free", a/1024, t/1024}' /proc/meminfo)"
  echo "  $d    $c    ${C_DIM}RAM $mem${C_RESET}"
  if [[ -f "$COMPOSE_FILE" ]]; then
    echo "  $(term_state mt4)    $(term_state mt5)"
  fi
}

# -----------------------------------------------------------------------------
# Access information
# -----------------------------------------------------------------------------
mostrar_acesso() {
  local pw cn tz ip
  pw="$(env_get VNC_PASSWORD)"; pw="${pw:0:8}"; cn="$(container_name)"; tz="$(env_get TZ)"
  ip="$(server_ip)"
  echo "  ${C_BOLD}MetaTrader access (noVNC)${C_RESET}"
  rule
  echo "  Container:   $cn"
  echo "  Timezone:    ${tz:-?}"
  echo "  VNC password:${C_YELLOW} ${pw:-'(see .env)'}${C_RESET}"
  echo
  echo "  noVNC is bound to localhost only (not exposed to the internet). To access it,"
  echo "  open an SSH tunnel ${C_BOLD}on your computer${C_RESET} (Windows/Mac/Linux):"
  echo
  echo "    ${C_CYAN}ssh -N -p $SSH_PORT -L 6080:127.0.0.1:6080 root@$ip${C_RESET}"
  echo
  echo "  then open in your browser:"
  echo
  echo "    ${C_CYAN}http://localhost:6080/vnc.html?autoconnect=1&resize=scale${C_RESET}"
  echo
  echo "  ${C_DIM}Tip: keep the tunnel terminal open while using noVNC.${C_RESET}"
}

# -----------------------------------------------------------------------------
# Timezone
# -----------------------------------------------------------------------------
escolher_tz() {
  local atual opt chosen="America/Sao_Paulo"
  atual="$(env_get TZ)"; atual="${atual:-America/Sao_Paulo}"
  echo "  ${C_BOLD}Container timezone${C_RESET} ${C_DIM}(current: $atual)${C_RESET}"
  echo "    1) America/Sao_Paulo  (default BR)"
  echo "    2) UTC"
  echo "    3) Use host timezone"
  echo "    4) Other (type, e.g. Europe/London)"
  echo "    5) Keep current"
  read -rp "  Option [1-5] (Enter=5): " opt || true
  case "${opt:-5}" in
    1) chosen="America/Sao_Paulo" ;;
    2) chosen="UTC" ;;
    3)
      if [[ -f /etc/timezone ]]; then chosen="$(tr -d '[:space:]' < /etc/timezone)"
      elif command -v timedatectl >/dev/null 2>&1; then chosen="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
      fi
      chosen="${chosen:-America/Sao_Paulo}" ;;
    4)
      read -rp "  Enter TZ: " chosen || true
      chosen="${chosen:-$atual}" ;;
    *) chosen="$atual" ;;
  esac
  if [[ ! -e "/usr/share/zoneinfo/$chosen" && "$chosen" != "UTC" ]]; then
    warn "TZ '$chosen' does not exist in /usr/share/zoneinfo; keeping $atual"
    chosen="$atual"
  fi
  env_set TZ "$chosen"
  ok "TZ=$chosen"
}

# -----------------------------------------------------------------------------
# Wine version
# -----------------------------------------------------------------------------
escolher_wine() {
  local atual def=1 opt v
  atual="$(env_get WINE_VERSION)"; atual="${atual:-10.0.0.0~jammy-1}"
  [[ "$atual" == 11.* ]] && def=2
  echo "  ${C_BOLD}Wine version${C_RESET} ${C_DIM}(current: ${atual%%.*})${C_RESET}"
  echo "    1) Wine 10  ${C_GREEN}(recommended)${C_RESET}  ${C_DIM}— works with the official MetaQuotes installer${C_RESET}"
  echo "    2) Wine 11  ${C_DIM}— newer; the official MetaQuotes installer may fail${C_RESET}"
  read -rp "  Option [1-2] (Enter=$def): " opt || true
  case "${opt:-$def}" in
    2) v="11.0.0.0~jammy-1" ;;
    *) v="10.0.0.0~jammy-1" ;;
  esac
  env_set WINE_VERSION "$v"
  ok "Wine ${v%%.*} (WINE_VERSION=$v)"
}

# -----------------------------------------------------------------------------
# Project file generation
# -----------------------------------------------------------------------------
gerar_arquivos() {
  mkdir -p "$APP_DIR"/{docker/bin,docker/lib,scripts,data/{prefix-mt4,prefix-mt5,logs,installers}}

  cat > "$APP_DIR/.dockerignore" <<'EOF'
data/
backups/
scripts/
robos/
.env
*.log
EOF

  cat > "$APP_DIR/Dockerfile" <<'EOF'
FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
ARG WINE_BRANCH=stable
# Pinned Wine version: the official MetaQuotes installer fails on Wine 11
# ("A debugger has been found running"). Empty = always the latest.
ARG WINE_VERSION=10.0.0.0~jammy-1
ARG WINETRICKS_VERSION=20240105
ARG MT_UID=1000
ARG MT_GID=1000

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    TZ=America/Sao_Paulo \
    DISPLAY=:99 \
    WINEDEBUG=-all \
    MALLOC_ARENA_MAX=2 \
    PATH="/opt/mt/bin:${PATH}"

RUN set -eux; \
    dpkg --add-architecture i386; \
    apt-get update; \
    apt-get install -y --no-install-recommends ca-certificates wget gnupg; \
    mkdir -pm755 /etc/apt/keyrings; \
    wget -qO /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key; \
    wget -qNP /etc/apt/sources.list.d/ https://dl.winehq.org/wine-builds/ubuntu/dists/jammy/winehq-jammy.sources; \
    apt-get update; \
    V=""; if [ -n "${WINE_VERSION}" ]; then V="=${WINE_VERSION}"; fi; \
    apt-get install -y --no-install-recommends \
        "winehq-${WINE_BRANCH}${V}" "wine-${WINE_BRANCH}${V}" \
        "wine-${WINE_BRANCH}-i386${V}" "wine-${WINE_BRANCH}-amd64${V}" \
        xvfb x11vnc x11-utils fluxbox \
        novnc websockify supervisor \
        cabextract unzip p7zip-full \
        procps tzdata fonts-liberation; \
    ln -sf vnc.html /usr/share/novnc/index.html; \
    apt-get autoremove -y; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /tmp/*

RUN wget -qO /usr/local/bin/winetricks \
      "https://raw.githubusercontent.com/Winetricks/winetricks/${WINETRICKS_VERSION}/src/winetricks" && \
    head -n1 /usr/local/bin/winetricks | grep -q '^#!' && \
    chmod 755 /usr/local/bin/winetricks

RUN groupadd -g "${MT_GID}" mt && \
    useradd -m -u "${MT_UID}" -g mt -s /bin/bash mt && \
    mkdir -p /home/mt/prefix/mt4 /home/mt/prefix/mt5 /home/mt/logs /home/mt/installers /tmp/.X11-unix && \
    chmod 1777 /tmp/.X11-unix && \
    chown -R mt:mt /home/mt

COPY docker/bin/ /opt/mt/bin/
COPY docker/lib/ /opt/mt/lib/
COPY docker/supervisord.conf /etc/supervisor/mt.conf
RUN chmod 755 /opt/mt/bin/* && chmod 644 /opt/mt/lib/common.sh /etc/supervisor/mt.conf

USER mt
WORKDIR /home/mt
EXPOSE 6080
STOPSIGNAL SIGTERM
ENTRYPOINT ["/opt/mt/bin/mt-entrypoint"]
EOF

  cat > "$APP_DIR/docker-compose.yml" <<'EOF'
name: mt-docker

services:
  mt:
    build:
      context: .
      args:
        WINE_BRANCH: ${WINE_BRANCH:-stable}
        WINE_VERSION: ${WINE_VERSION:-10.0.0.0~jammy-1}
    image: ${IMAGE_NAME:-mt-trader:local}
    container_name: ${CONTAINER_NAME:-mt}
    hostname: mt-docker
    restart: unless-stopped
    init: true
    stop_signal: SIGTERM
    stop_grace_period: 60s

    ports:
      - "${BIND_ADDR:-127.0.0.1}:${NOVNC_PORT:-6080}:6080"

    environment:
      TZ: "${TZ:-America/Sao_Paulo}"
      RESOLUTION: "${RESOLUTION:-1024x600x16}"
      VNC_PASSWORD: "${VNC_PASSWORD:?VNC_PASSWORD not set; run scripts/setup-host.sh}"
      EA_DEPS_MT4: "${EA_DEPS_MT4:-corefonts vcrun2019 winhttp gdiplus msxml6}"
      EA_DEPS_MT5: "${EA_DEPS_MT5:-corefonts vcrun2019 winhttp gdiplus msxml6}"
      MT4_ARCH: "${MT4_ARCH:-win64}"

    volumes:
      - ./data/prefix-mt4:/home/mt/prefix/mt4
      - ./data/prefix-mt5:/home/mt/prefix/mt5
      - ./data/logs:/home/mt/logs
      - ./data/installers:/home/mt/installers:ro

    shm_size: ${SHM_SIZE:-128m}
    mem_limit: ${MEM_LIMIT:-800m}
    memswap_limit: ${MEMSWAP_LIMIT:-2800m}
    cpus: ${CPUS:-1.0}
    pids_limit: ${PIDS_LIMIT:-1024}
    ulimits:
      nofile:
        soft: 65536
        hard: 65536

    cap_drop: [ALL]
    security_opt:
      - no-new-privileges:true

    healthcheck:
      test: ["CMD", "bash", "-c", "xdpyinfo -display :99 >/dev/null 2>&1 && (exec 3<>/dev/tcp/127.0.0.1/5900) 2>/dev/null && (exec 3<>/dev/tcp/127.0.0.1/6080) 2>/dev/null"]
      interval: 60s
      timeout: 10s
      retries: 3
      start_period: 120s

    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
EOF

  cat > "$APP_DIR/docker/lib/common.sh" <<'EOF'
#!/usr/bin/env bash
LOG_DIR="${LOG_DIR:-/home/mt/logs}"
LOG_FILE="$LOG_DIR/mt-docker.log"
export WINEDEBUG="${WINEDEBUG:--all}"
export WINEDLLOVERRIDES="${WINEDLLOVERRIDES:-winemenubuilder.exe=d}"
export DISPLAY="${DISPLAY:-:99}"

log() {
  local lvl="$1" comp="$2"; shift 2
  local line
  line="$(date '+%Y-%m-%dT%H:%M:%S%z') [$lvl] [$comp] $*"
  echo "$line"
  echo "$line" >> "$LOG_FILE" 2>/dev/null || true
}
die() { log ERROR "$1" "${*:2}"; exit 1; }

retry() {
  local n="$1" d="$2" i; shift 2
  for ((i = 1; i <= n; i++)); do
    if "$@"; then return 0; fi
    log WARN retry "attempt $i/$n failed: $*"
    sleep $((d * i))
  done
  return 1
}

mem_limit_mb() {
  local v=max
  if   [[ -r /sys/fs/cgroup/memory.max ]]; then v="$(</sys/fs/cgroup/memory.max)"
  elif [[ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]]; then v="$(</sys/fs/cgroup/memory/memory.limit_in_bytes)"
  fi
  if [[ "$v" == "max" || ! "$v" =~ ^[0-9]+$ || ${#v} -gt 12 ]]; then
    awk '/^MemTotal:/{print int($2/1024)}' /proc/meminfo
  else
    echo $(( v / 1048576 ))
  fi
}

load_terminal() {
  local default_deps="corefonts vcrun2019 winhttp gdiplus msxml6"
  case "${1:-}" in
    mt4)
      MT_ID=mt4; MT_NAME="MetaTrader 4"; MT_ARCH="${MT4_ARCH:-win64}"; MT_EXE_NAME="terminal.exe"
      MT_URL="https://download.mql5.com/cdn/web/metaquotes.software.corp/mt4/mt4setup.exe"
      MT_DEPS="${EA_DEPS_MT4:-$default_deps}" ;;
    mt5)
      MT_ID=mt5; MT_NAME="MetaTrader 5"; MT_ARCH="win64"; MT_EXE_NAME="terminal64.exe"
      MT_URL="https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe"
      MT_DEPS="${EA_DEPS_MT5:-$default_deps}" ;;
    *) die lib "invalid terminal: '${1:-}'" ;;
  esac
  export WINEPREFIX="/home/mt/prefix/$MT_ID"
  export WINEARCH="$MT_ARCH"
  MT_MARKER="$WINEPREFIX/.mt_exe_path"
}

find_exe() {
  find "$WINEPREFIX/drive_c" -maxdepth 6 -type f -iname "$MT_EXE_NAME" \
       -not -ipath '*/windows/*' -print -quit 2>/dev/null
}
EOF

  cat > "$APP_DIR/docker/bin/mt-entrypoint" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source /opt/mt/lib/common.sh
COMP="entrypoint"

log INFO "$COMP" "starting (uid=$(id -u))"

for d in /home/mt/prefix/mt4 /home/mt/prefix/mt5 /home/mt/logs; do  [[ -w "$d" ]] || die "$COMP" "no write permission on $d. On host: chown -R 1000:1000 /opt/mt-docker/data"
done

[[ -n "${VNC_PASSWORD:-}" ]] || die "$COMP" "VNC_PASSWORD is empty. Run scripts/setup-host.sh"
(( ${#VNC_PASSWORD} >= 8 )) || die "$COMP" "VNC_PASSWORD must be at least 8 characters"
if (( ${#VNC_PASSWORD} > 8 )); then
  log WARN "$COMP" "VNC_PASSWORD has ${#VNC_PASSWORD} chars; x11vnc uses only the first 8"
  VNC_PASSWORD="${VNC_PASSWORD:0:8}"
fi
( umask 077; printf '%s\n' "$VNC_PASSWORD" > /tmp/vnc.pass )
unset VNC_PASSWORD

rm -f /tmp/.X99-lock /tmp/.X11-unix/X99 /tmp/supervisor.sock /tmp/supervisord.pid

LIMIT="$(mem_limit_mb)"
log INFO "$COMP" "effective memory limit: ${LIMIT}MB"
(( LIMIT >= 700 )) || log WARN "$COMP" "memory < 700MB: MT5 + Wine may hit OOM"

export RESOLUTION="${RESOLUTION:-1024x600x16}"
log INFO "$COMP" "starting supervisord (resolution $RESOLUTION)"
exec supervisord -c /etc/supervisor/mt.conf
EOF

  cat > "$APP_DIR/docker/bin/mt-sv" <<'EOF'
#!/usr/bin/env bash
exec supervisorctl -s unix:///tmp/supervisor.sock "$@"
EOF

  cat > "$APP_DIR/docker/bin/run-terminal" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source /opt/mt/lib/common.sh

ID="${1:?usage: run-terminal mt4|mt5}"
load_terminal "$ID"
COMP="run-$ID"
WPID=""

stop() {
  log INFO "$COMP" "SIGTERM received: shutting down $MT_NAME gracefully"
  WINEPREFIX="$WINEPREFIX" wine taskkill /IM "$MT_EXE_NAME" 2>/dev/null || true
  [[ -n "$WPID" ]] && kill -TERM "$WPID" 2>/dev/null || true
  if [[ -n "$WPID" ]]; then
    for _ in $(seq 1 45); do
      kill -0 "$WPID" 2>/dev/null || break
      sleep 1
    done
  fi
  if [[ -n "$WPID" ]] && kill -0 "$WPID" 2>/dev/null; then
    WINEPREFIX="$WINEPREFIX" wineserver -k 2>/dev/null || true
  fi
  [[ -n "$WPID" ]] && wait "$WPID" 2>/dev/null || true
  WINEPREFIX="$WINEPREFIX" wineserver -w 2>/dev/null || true
  exit 0
}
trap stop TERM INT

n=0
until [[ -s "$MT_MARKER" ]]; do
  if (( n % 30 == 0 )); then
    log WARN "$COMP" "$MT_NAME not installed. Run: docker compose exec mt mt-install $ID"
  fi
  n=$((n + 1))
  sleep 10 & wait $!
done

EXE="$(<"$MT_MARKER")"
[[ -f "$EXE" ]] || die "$COMP" "executable missing: $EXE (reinstall: mt-install $ID --force)"

log INFO "$COMP" "starting $MT_NAME: $EXE"
cd "$(dirname "$EXE")"
wine "$EXE" /portable &
WPID=$!

rc=0
wait "$WPID" || rc=$?
log WARN "$COMP" "$MT_NAME exited (rc=$rc); supervisor will restart"
sleep 10
exit "$rc"
EOF

  cat > "$APP_DIR/docker/bin/mt-install" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source /opt/mt/lib/common.sh
COMP="install"

usage() {
  cat <<'USO'
Usage: mt-install mt4|mt5 [--force] [--skip-deps] [--installer PATH]
USO
}

ID="${1:-}"
[[ "$ID" == "-h" || "$ID" == "--help" ]] && { usage; exit 0; }
[[ -n "$ID" ]] || { usage; exit 1; }
shift
FORCE=0; SKIP_DEPS=0; LOCAL_INSTALLER=""
while (($#)); do
  case "$1" in
    --force) FORCE=1 ;;
    --skip-deps) SKIP_DEPS=1 ;;
    --installer) LOCAL_INSTALLER="${2:?}"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage; die "$COMP" "unknown option: $1" ;;
  esac
  shift
done

load_terminal "$ID"

RUNFLAG=/tmp/mt-install.running
if [[ -f "$RUNFLAG" ]] && kill -0 "$(cat "$RUNFLAG")" 2>/dev/null; then
  die "$COMP" "another installation is already running"
fi
echo $$ > "$RUNFLAG"
INSTALLER="/tmp/mt-setup-$ID.exe"
cleanup() {
  rm -f "$RUNFLAG" "$INSTALLER"
  if ! pgrep -fi "${MT_EXE_NAME:-terminal}" >/dev/null 2>&1; then
    WINEPREFIX="${WINEPREFIX:-}" wineserver -k 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'log ERROR "$COMP" "failed at line $LINENO"' ERR

LIMIT="$(mem_limit_mb)"
(( LIMIT >= 600 )) || die "$COMP" "memory limit (${LIMIT}MB) < 600MB"
xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 || die "$COMP" "display $DISPLAY unavailable"

if [[ -s "$MT_MARKER" && $FORCE -eq 0 ]]; then
  log INFO "$COMP" "$MT_NAME already installed: nothing to do"
  exit 0
fi
if (( FORCE )) && pgrep -fi "$MT_EXE_NAME" >/dev/null; then
  die "$COMP" "$MT_NAME is running. Stop it: mt-sv stop $ID"
fi
if (( FORCE )); then rm -f "$MT_MARKER"; fi

if [[ ! -f "$WINEPREFIX/.mt_prefix_ready" ]]; then
  log INFO "$COMP" "creating $MT_ARCH prefix"
  WINEDLLOVERRIDES="mscoree,mshtml=d;winemenubuilder.exe=d" timeout 300 wineboot --init
  WINEPREFIX="$WINEPREFIX" wineserver -w
  touch "$WINEPREFIX/.mt_prefix_ready"
fi

if (( SKIP_DEPS == 0 )); then
  mkdir -p "$WINEPREFIX/.deps"
  failed=()
  for dep in $MT_DEPS; do
    if [[ -f "$WINEPREFIX/.deps/$dep" ]]; then
      log INFO deps "$dep already installed"; continue
    fi
    log INFO deps "installing $dep"
    if retry 2 10 timeout 2400 winetricks -q "$dep"; then
      touch "$WINEPREFIX/.deps/$dep"
    else
      failed+=("$dep")
      log ERROR deps "failed: $dep"
      log WARN deps "if the Microsoft URL changed, try updating WINETRICKS_VERSION in the Dockerfile"
    fi
    WINEPREFIX="$WINEPREFIX" wineserver -w || true
  done
  if [[ ! -f "$WINEPREFIX/.deps/win10" ]]; then
    if winetricks -q win10; then touch "$WINEPREFIX/.deps/win10"; fi
    WINEPREFIX="$WINEPREFIX" wineserver -w || true
  fi
  if ((${#failed[@]} > 0)); then
    log WARN deps "failed: ${failed[*]}"
  fi
fi

if [[ -n "$LOCAL_INSTALLER" ]]; then
  [[ -f "$LOCAL_INSTALLER" ]] || die "$COMP" "installer not found: $LOCAL_INSTALLER"
  cp "$LOCAL_INSTALLER" "$INSTALLER"
else
  log INFO "$COMP" "downloading $MT_URL"
  retry 3 5 wget --timeout=30 --tries=1 -q -O "$INSTALLER" "$MT_URL" || die "$COMP" "download failed"
fi
size="$(stat -c %s "$INSTALLER")"
(( size >= 200000 )) || die "$COMP" "installer too small (${size} bytes)"
[[ "$(head -c2 "$INSTALLER")" == "MZ" ]] || die "$COMP" "header is not a Windows executable (MZ)"

log INFO "$COMP" "running installer (watch via noVNC)"
timeout 900 wine "$INSTALLER" /auto >> "$LOG_DIR/setup-$ID.log" 2>&1 &
SETUP_PID=$!
terminal_seen=0
for ((i = 0; i < 180; i++)); do
  if pgrep -fi "$MT_EXE_NAME" >/dev/null; then
    log INFO "$COMP" "terminal started; waiting 90s for MQL/bases extraction"
    sleep 90
    terminal_seen=1
    break
  fi
  if ! kill -0 "$SETUP_PID" 2>/dev/null; then
    log INFO "$COMP" "installer finished; waiting up to 60s for terminal"
    for ((j = 0; j < 12; j++)); do
      if pgrep -fi "$MT_EXE_NAME" >/dev/null; then
        log INFO "$COMP" "terminal started; waiting 90s for MQL/bases extraction"
        sleep 90
        terminal_seen=1
        break 2
      fi
      sleep 5
    done
    break
  fi
  sleep 5
done
(( terminal_seen )) || log WARN "$COMP" "terminal not detected in time"

if kill -0 "$SETUP_PID" 2>/dev/null; then
  kill -TERM "$SETUP_PID" 2>/dev/null || true
  sleep 3
  wait "$SETUP_PID" 2>/dev/null || true
fi

EXE="$(find_exe || true)"
if [[ -z "$EXE" ]]; then
  find "$WINEPREFIX/drive_c" -iname 'terminal*.exe' 2>/dev/null | head -20 >> "$LOG_DIR/setup-$ID.log" || true
  die "$COMP" "$MT_EXE_NAME not found (see $LOG_DIR/setup-$ID.log)"
fi

if pgrep -fi "$MT_EXE_NAME" >/dev/null; then
  log INFO "$COMP" "closing orphan terminal so supervisor can take over"
  WINEPREFIX="$WINEPREFIX" wine taskkill /IM "$MT_EXE_NAME" 2>/dev/null || true
  for _ in $(seq 1 30); do
    pgrep -fi "$MT_EXE_NAME" >/dev/null || break
    sleep 1
  done
  if pgrep -fi "$MT_EXE_NAME" >/dev/null; then
    WINEPREFIX="$WINEPREFIX" wineserver -k 2>/dev/null || true
    WINEPREFIX="$WINEPREFIX" wineserver -w 2>/dev/null || true
  fi
fi

WINEPREFIX="$WINEPREFIX" wineserver -w 2>/dev/null || true
sleep 2
echo "$EXE" > "$MT_MARKER"
chmod 700 "$WINEPREFIX"
rm -rf "$HOME/.cache/winetricks" "$HOME/.cache/fontconfig"
log INFO "$COMP" "$MT_NAME installed: $EXE"
EOF

  cat > "$APP_DIR/docker/supervisord.conf" <<'EOF'
[supervisord]
nodaemon=true
logfile=/dev/stdout
logfile_maxbytes=0
pidfile=/tmp/supervisord.pid
loglevel=info

[unix_http_server]
file=/tmp/supervisor.sock
chmod=0700

[rpcinterface:supervisor]
supervisor.rpcinterface_factory=supervisor.rpcinterface:make_main_rpcinterface

[supervisorctl]
serverurl=unix:///tmp/supervisor.sock

[program:xvfb]
command=Xvfb :99 -screen 0 %(ENV_RESOLUTION)s -ac -nolisten tcp -noreset
priority=10
autorestart=true
startsecs=3
stopwaitsecs=10
redirect_stderr=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0

[program:fluxbox]
command=bash -c "for i in $(seq 1 30); do xdpyinfo -display :99 >/dev/null 2>&1 && exec fluxbox; sleep 1; done; exit 1"
environment=DISPLAY=":99"
priority=20
autorestart=true
startsecs=3
redirect_stderr=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0

[program:x11vnc]
command=bash -c "for i in $(seq 1 30); do xdpyinfo -display :99 >/dev/null 2>&1 && exec x11vnc -display :99 -forever -rfbport 5900 -localhost -passwdfile /tmp/vnc.pass -noxdamage -nolookup -quiet; sleep 1; done; exit 1"
priority=30
autorestart=true
startsecs=3
redirect_stderr=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0

[program:novnc]
command=websockify --web=/usr/share/novnc 6080 127.0.0.1:5900
priority=40
autorestart=true
startsecs=3
redirect_stderr=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0

[program:mt4]
command=/opt/mt/bin/run-terminal mt4
environment=DISPLAY=":99"
priority=50
autorestart=true
startsecs=15
startretries=10
stopsignal=TERM
stopwaitsecs=45
killasgroup=false
redirect_stderr=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0

[program:mt5]
command=/opt/mt/bin/run-terminal mt5
environment=DISPLAY=":99"
priority=60
autorestart=true
startsecs=15
startretries=10
stopsignal=TERM
stopwaitsecs=45
killasgroup=false
redirect_stderr=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
EOF

  cat > "$APP_DIR/scripts/setup-host.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$APP_DIR/.env"
log() { echo "$(date '+%Y-%m-%dT%H:%M:%S%z') [$1] [setup-host] ${*:2}"; }
die() { log ERROR "$*"; exit 1; }

[[ $EUID -eq 0 ]] || die "run as root: sudo $0"
command -v docker >/dev/null 2>&1 || die "Docker not found"
docker compose version >/dev/null 2>&1 || die "Docker Compose v2 not found"

TOTAL_MB="$(awk '/^MemTotal:/{print int($2/1024)}' /proc/meminfo)"
SWAP_MB="$(awk '/^SwapTotal:/{print int($2/1024)}' /proc/meminfo)"
AVAIL_MB="$(awk '/^MemAvailable:/{print int($2/1024)}' /proc/meminfo)"
CORES="$(nproc)"
if   (( TOTAL_MB <= 2048 )); then SWAP_TARGET=2048
elif (( TOTAL_MB <= 4096 )); then SWAP_TARGET=1024
else SWAP_TARGET=0; fi
log INFO "RAM=${TOTAL_MB}MB available=${AVAIL_MB}MB swap=${SWAP_MB}MB cpus=${CORES}"

if (( AVAIL_MB < 800 )); then
  log WARN "MemAvailable=${AVAIL_MB}MB < 800MB: VPS is overloaded right now; container may start slowly or hit temporary OOM"
fi

make_swapfile() {
  local mb="$1"
  rm -f /swapfile
  fallocate -l "${mb}M" /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count="$mb" status=none
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
}
if (( SWAP_TARGET > 0 && SWAP_MB < SWAP_TARGET - 100 )); then
  NEED=$(( SWAP_TARGET - SWAP_MB ))
  if swapon --show=NAME --noheadings 2>/dev/null | grep -qx '/swapfile'; then
    log WARN "/swapfile is already active but small (${SWAP_MB}MB); will not recreate it while in use"
  else
    log INFO "creating ${NEED}MB swap"
    [[ -f /swapfile ]] || make_swapfile "$NEED"
    if ! swapon /swapfile 2>/dev/null; then
      make_swapfile "$NEED"
      swapon /swapfile 2>/dev/null || log WARN "swapon failed (OpenVZ/LXC?)"
    fi
    grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    SWAP_MB="$(awk '/^SwapTotal:/{print int($2/1024)}' /proc/meminfo)"
  fi
fi

cat > /etc/sysctl.d/99-mt-docker.conf <<'SYS'
vm.swappiness=20
vm.vfs_cache_pressure=50
SYS
sysctl -q -p /etc/sysctl.d/99-mt-docker.conf >/dev/null 2>&1 || log WARN "sysctl not applied"

RESERVE=$(( TOTAL_MB * 15 / 100 )); (( RESERVE >= 200 )) || RESERVE=200
MEM_MB=$(( TOTAL_MB - RESERVE ))
(( MEM_MB >= 600 )) || log WARN "only ${MEM_MB}MB for the container"
SWAP_ALLOW=$(( SWAP_MB > 2048 ? 2048 : SWAP_MB ))
if (( SWAP_ALLOW == 0 )); then
  SWAP_ALLOW=512
  log WARN "host has no swap; memswap_limit will use +512 MB headroom"
fi
MEMSWAP_MB=$(( MEM_MB + SWAP_ALLOW ))
SHM=$(( TOTAL_MB <= 2048 ? 128 : 512 ))
CPUS="$(awk -v n="$CORES" 'BEGIN{ if (n<=1) print "1.0"; else printf "%.1f", n-0.5 }')"

mkdir -p "$APP_DIR"/data/{prefix-mt4,prefix-mt5,logs,installers}
chown -R 1000:1000 "$APP_DIR/data"
chmod 700 "$APP_DIR"/data/prefix-mt4 "$APP_DIR"/data/prefix-mt5
chmod 750 "$APP_DIR"/data/logs "$APP_DIR"/data/installers
chmod 755 "$APP_DIR"/scripts/*.sh

touch "$ENV_FILE"; chmod 600 "$ENV_FILE"

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
default_kv MT4_ARCH "win64"
# win32 breaks 64-bit installers ("Bad EXE format"); win64 runs both
[[ "$(get_kv MT4_ARCH)" == "win32" ]] && set_kv MT4_ARCH win64

if [[ -z "$(get_kv VNC_PASSWORD)" ]]; then
  PW="$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | cut -c1-8)"
  set_kv VNC_PASSWORD "$PW"
  log INFO "VNC password generated: $PW (SAVE IT NOW)"
else
  log INFO "existing VNC password preserved"
fi

# Daily cleanup: old logs (>15 days) deleted; huge logs (>50MB) truncated
CRON_MARKER="# mt-docker-log-cleanup"
CRON_CMD="0 3 * * * find ${APP_DIR}/data -type f -name '*.log' -mtime +15 -delete; find ${APP_DIR}/data/logs -type f -name '*.log' -size +50M -exec truncate -s 0 {} + ${CRON_MARKER}"
if command -v crontab >/dev/null 2>&1; then
  { crontab -l 2>/dev/null | grep -vF "$CRON_MARKER" || true; echo "$CRON_CMD"; } | crontab -
  log INFO "log cleanup cron installed/updated (daily 03:00)"
else
  log WARN "crontab not available; automatic log cleanup not configured"
fi

log INFO "limits: mem=${MEM_MB}m memswap=${MEMSWAP_MB}m cpus=${CPUS} shm=${SHM}m"
log INFO "ready"
EOF

  cat > "$APP_DIR/scripts/backup.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# Folder: BACKUP_DIR > .backup_dir file (written by the menu) > $ROOT/backups
# BACKUP_KEEP=N keeps only the N most recent; default 0 = delete nothing (clean up by hand).
KEEP="${BACKUP_KEEP:-0}"
DEST="${BACKUP_DIR:-}"
if [[ -z "$DEST" && -s "$ROOT/.backup_dir" ]]; then DEST="$(<"$ROOT/.backup_dir")"; fi
DEST="${DEST:-$ROOT/backups}"
mkdir -p "$DEST"
TS="$(date +%Y%m%d-%H%M%S)"
OUT="$DEST/mt-backup-$TS.tar.gz"
log() { echo "$(date '+%Y-%m-%dT%H:%M:%S%z') [$1] [backup] ${*:2}"; }

NEED="$(du -sm data 2>/dev/null | cut -f1 || echo 0)"; FREE="$(df -Pm "$DEST" | awk 'NR==2{print $4}')"
(( FREE > NEED / 2 )) || { log ERROR "insufficient space"; exit 1; }

# drive_c (terminal, account, EAs) + Wine registry + installer markers,
# so the backup restores a full terminal even after uninstall.
TARGETS=()
for p in prefix-mt4 prefix-mt5; do
  [[ -d "data/$p/drive_c" ]] || continue
  TARGETS+=("$p/drive_c")
  for extra in system.reg user.reg userdef.reg .mt_exe_path .mt_prefix_ready .deps dosdevices; do
    if [[ -e "data/$p/$extra" || -L "data/$p/$extra" ]]; then TARGETS+=("$p/$extra"); fi
  done
done
if ((${#TARGETS[@]} == 0)); then
  log WARN "no prefix found; backup skipped"
  exit 0
fi

umask 077
log INFO "backup → $OUT (${TARGETS[*]})"
rc=0
tar -C data -czf "$OUT" \
    --exclude='Tester' --exclude='tester' \
    --ignore-failed-read \
    "${TARGETS[@]}" 2>/dev/null || rc=$?
if (( rc == 1 )); then log WARN "files changed during copy"; rc=0; fi
(( rc == 0 )) || { log ERROR "tar failed"; rm -f "$OUT"; exit "$rc"; }

chown 1000:1000 "$OUT" 2>/dev/null || true
chmod 600 "$OUT"
log INFO "ok: $(du -h "$OUT" | cut -f1)  $OUT"
if (( KEEP > 0 )); then
  ls -1t "$DEST"/mt-backup-*.tar.gz 2>/dev/null | tail -n +"$((KEEP + 1))" | while read -r old; do
    rm -f -- "$old"; log INFO "removed old: $old"
  done
fi
EOF

  cat > "$APP_DIR/scripts/update.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
log() { echo "$(date '+%Y-%m-%dT%H:%M:%S%z') [$1] [update] ${*:2}"; }

log INFO "backup before update"
"$ROOT/scripts/backup.sh"

log INFO "rebuilding image"
docker compose build --pull
docker compose up -d
log INFO "done"
EOF

  chmod 755 "$APP_DIR"/docker/bin/* "$APP_DIR"/scripts/*.sh
  chmod 644 "$APP_DIR"/docker/lib/common.sh "$APP_DIR"/docker/supervisord.conf \
            "$APP_DIR"/Dockerfile "$APP_DIR"/docker-compose.yml "$APP_DIR"/.dockerignore
}

# Install the "mt-menu" shortcut (copy of this script in $APP_DIR/scripts)
instalar_atalho() {
  local alvo="$APP_DIR/scripts/mt-menu.sh"
  if [[ "$SELF" != "$alvo" ]]; then
    cp -f "$SELF" "$alvo" 2>/dev/null && chmod 755 "$alvo" || return 0
  fi
  printf '#!/usr/bin/env bash\nexec bash %q "$@"\n' "$alvo" > "$MENU_BIN" 2>/dev/null \
    && chmod 755 "$MENU_BIN" 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# Step 1 — Base installation
# -----------------------------------------------------------------------------
etapa_instalar_base() {
  title "1 · Base installation"
  require_root

  case "$(. /etc/os-release 2>/dev/null; echo "${ID:-?}")" in
    ubuntu|debian) ;;
    *) warn "System is not Ubuntu/Debian; the script was designed for them." ;;
  esac

  if ! command -v curl >/dev/null 2>&1; then
    info "Installing curl..."
    apt-get update -qq && apt-get install -y -qq curl ca-certificates || { err "could not install curl"; return 1; }
  fi

  if ! command -v docker >/dev/null 2>&1; then
    run_spin "Installing Docker (get.docker.com)" /tmp/mt-docker-install.log \
      bash -c 'curl -fsSL https://get.docker.com | DEBIAN_FRONTEND=noninteractive sh' || return 1
  fi
  command -v systemctl >/dev/null 2>&1 && systemctl enable --now docker >/dev/null 2>&1
  docker compose version >/dev/null 2>&1 || { err "Docker Compose v2 not found"; return 1; }
  docker info >/dev/null 2>&1 || { err "Docker daemon is not running: systemctl start docker"; return 1; }
  ok "Docker OK (enabled on boot)"

  mkdir -p "$APP_DIR"
  local free_gb
  free_gb="$(df -BG "$APP_DIR" 2>/dev/null | awk 'NR==2{gsub(/G/,"",$4); print $4+0}')"
  if [[ -z "$free_gb" || "$free_gb" == "0" ]]; then
    warn "could not measure free space; continuing"
  elif (( free_gb < 10 )); then
    err "insufficient space on $APP_DIR: ${free_gb}GB free (minimum 10GB)"; return 1
  else
    ok "Disk space: ${free_gb}GB free"
  fi

  info "Generating files in $APP_DIR"
  gerar_arquivos || { err "failed to generate files"; return 1; }

  info "Configuring host (swap, limits, .env, cron)..."
  bash "$APP_DIR/scripts/setup-host.sh" 2>&1 | sed 's/^/    /'
  if [[ "${PIPESTATUS[0]}" -ne 0 ]]; then err "setup-host failed"; return 1; fi
  echo
  escolher_tz
  echo
  escolher_wine
  instalar_atalho

  echo
  cd "$APP_DIR" || return 1
  run_spin "Building Docker image (5–15 min the first time)" "$APP_DIR/data/logs/host-build.log" \
    timeout 1800 docker compose -f "$COMPOSE_FILE" build --progress plain || return 1
  dc up -d >/dev/null 2>&1 || { err "docker compose up failed"; return 1; }

  if wait_healthy; then
    printf '\r\033[K'; ok "Container healthy"
  else
    printf '\r\033[K'; warn "Healthcheck did not become healthy in time. See: mt-menu → 4 (Status)"
  fi

  echo
  ok "${C_BOLD}Base installation complete${C_RESET}"
  echo
  mostrar_acesso
  echo
  echo "  ${C_BOLD}Next step:${C_RESET} option 2 (install MT4/MT5), then option 3 (robots)."
  echo "  ${C_DIM}Shortcut to return to this menu: sudo mt-menu${C_RESET}"
}

# -----------------------------------------------------------------------------
# Step 2 — Install MT4 + MT5
# -----------------------------------------------------------------------------
instalar_terminal() { # instalar_terminal mt4|mt5
  local id="$1" args=() rc=0 log="$APP_DIR/data/logs/host-install-$1.log"

  # MT4 with a win32 prefix cannot run the 64-bit installer ("Bad EXE format").
  # If MT4 is not installed yet, migrate to win64 and recreate the prefix.
  if [[ "$id" == "mt4" && ! -s "$APP_DIR/data/prefix-mt4/.mt_exe_path" ]]; then
    local migrou=0
    if [[ "$(env_get MT4_ARCH)" != "win64" ]]; then env_set MT4_ARCH win64; migrou=1; fi
    if grep -qs '^#arch=win32' "$APP_DIR/data/prefix-mt4/system.reg"; then
      warn "Old MT4 prefix is win32; recreating as win64..."
      dc exec -T mt mt-sv stop mt4 >/dev/null 2>&1 || true
      find "$APP_DIR/data/prefix-mt4" -mindepth 1 -delete 2>/dev/null
      migrou=1
    fi
    if (( migrou )); then
      dc up -d --force-recreate >/dev/null 2>&1
      wait_supervisor || { err "container did not come back"; return 1; }
    fi
  fi

  if [[ -s "$APP_DIR/data/prefix-$id/.mt_exe_path" ]]; then
    warn "${id^^} is already installed."
    if confirm "Reinstall (--force)?"; then args+=(--force); else return 0; fi
  fi

  echo
  info "Installing ${id^^} — takes 10 to 30 min. You can watch via noVNC (option 7 shows how)."
  dc exec -T mt mt-sv stop "$id" >/dev/null 2>&1 || true
  sleep 2

  run_spin "Installing ${id^^}" "$log" dc exec -T mt mt-install "$id" "${args[@]}" || rc=$?

  # Restart the program in supervisor (it was stopped manually above)
  dc exec -T mt mt-sv start "$id" >/dev/null 2>&1 || true
  if (( rc == 0 )); then
    ok "${id^^} installed and starting"
  else
    err "${id^^} failed. Detailed log: $APP_DIR/data/logs/setup-$id.log"
  fi
  return "$rc"
}

# Remove a terminal: stop the program, kill the prefix wineserver and delete the
# entire prefix (terminal, account, EAs, Wine dependencies). Reinstall rebuilds everything.
remover_terminal() { # remover_terminal mt4|mt5
  local id="$1" dir="$APP_DIR/data/prefix-$1"
  if container_running; then
    dc exec -T mt mt-sv stop "$id" >/dev/null 2>&1 || true
    dc exec -T -e WINEPREFIX="/home/mt/prefix/$id" mt wineserver -k >/dev/null 2>&1 || true
    sleep 2
  fi
  find "$dir" -mindepth 1 -delete 2>/dev/null
  if [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
    ok "${id^^} removed"
  else
    err "could not delete everything in $dir"
    return 1
  fi
}

desinstalar_terminais() {
  local esc ids=() id existentes=()
  echo
  echo "  ${C_BOLD}Which terminal to uninstall?${C_RESET}"
  echo "    1) MT4"
  echo "    2) MT5"
  echo "    3) Both"
  echo "    0) Back"
  read -rp "  Option [0-3]: " esc || true
  case "${esc:-}" in
    1) ids=(mt4) ;;
    2) ids=(mt5) ;;
    3) ids=(mt4 mt5) ;;
    *) return 0 ;;
  esac

  for id in "${ids[@]}"; do
    if [[ -n "$(ls -A "$APP_DIR/data/prefix-$id" 2>/dev/null)" ]]; then
      existentes+=("$id")
    else
      info "${id^^} is already empty/not installed"
    fi
  done
  ((${#existentes[@]} > 0)) || return 0

  echo
  warn "This will DELETE ${existentes[*]^^}: the terminal, logged-in account, EAs/indicators and"
  warn "settings. Files in $ROBOS_DIR and backups are NOT affected."
  confirm "Confirm uninstall of ${existentes[*]^^}?" || { info "cancelled"; return 0; }

  for id in "${existentes[@]}"; do remover_terminal "$id"; done
  echo
  info "To install again, use this same option and choose Install."
}

etapa_instalar_terminais() {
  title "2 · MT4 / MT5 — install or uninstall"
  require_root
  need_base || return 1

  # container runs as uid 1000; wrong ownership on data/ causes restart loops
  chown -R 1000:1000 "$APP_DIR/data" 2>/dev/null
  chmod 700 "$APP_DIR/data/prefix-mt4" "$APP_DIR/data/prefix-mt5" 2>/dev/null

  local acao
  echo "  ${C_BOLD}What do you want to do?${C_RESET}"
  echo "    1) Install MT4 / MT5"
  echo "    2) Uninstall MT4 / MT5"
  echo "    0) Back"
  read -rp "  Option [0-2] (Enter=1): " acao || true
  case "${acao:-1}" in
    1) ;;
    2) desinstalar_terminais; return $? ;;
    *) return 0 ;;
  esac
  echo

  if ! container_running; then
    info "Container stopped — starting..."
    dc up -d >/dev/null 2>&1
  fi
  info "Waiting for internal services..."
  wait_supervisor || { err "supervisord did not respond; check the logs (menu 6)"; return 1; }

  echo
  echo "  ${C_BOLD}Which terminal to install?${C_RESET} ${C_DIM}(official MetaQuotes installer)${C_RESET}"
  echo "    1) MT4"
  echo "    2) MT5"
  echo "    3) Both (MT4 first, then MT5)"
  echo "    0) Back"
  local escolha
  read -rp "  Option [0-3]: " escolha || true
  case "${escolha:-}" in
    1) instalar_terminal mt4 ;;
    2) instalar_terminal mt5 ;;
    3)
      instalar_terminal mt4
      echo
      info "Waiting 30s for RAM to settle before MT5..."
      sleep 30
      instalar_terminal mt5
      ;;
    0) return 0 ;;
    *) warn "invalid option" ;;
  esac
}

# -----------------------------------------------------------------------------
# Step 3 — Robots / Indicators
# -----------------------------------------------------------------------------
# MQL folder of the terminal ON THE HOST. Because the terminal runs with /portable,
# data lives next to terminal.exe — we use the path from the marker, not "the first
# MQL4 that find finds" (which can be the AppData folder, ignored in portable mode).
mql_dest() { # mql_dest mt4|mt5 Experts|Indicators
  local id="$1" kind="$2" host_prefix marker exe_c exe_h dir mql
  host_prefix="$APP_DIR/data/prefix-$id"
  marker="$host_prefix/.mt_exe_path"
  [[ -s "$marker" ]] || return 1
  exe_c="$(<"$marker")"
  exe_h="${exe_c/#"/home/mt/prefix/$id"/$host_prefix}"
  [[ -f "$exe_h" ]] || return 1
  dir="$(dirname "$exe_h")"
  if [[ "$id" == "mt4" ]]; then mql="MQL4"; else mql="MQL5"; fi
  mkdir -p "$dir/$mql/$kind"
  chown 1000:1000 "$dir/$mql" "$dir/$mql/$kind" 2>/dev/null || true
  printf '%s' "$dir/$mql/$kind"
}

# Structure where you place the files; menu option 3 reads from here.
criar_estrutura_robos() {
  mkdir -p "$ROBOS_DIR"/{MT4,MT5}/{Experts,Indicators} "$ROBOS_DIR/sets" "$BACKUP_DIR" 2>/dev/null || true
  if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
    chown -R "$SUDO_USER:" "$ROBOS_DIR" 2>/dev/null || true
    chown "$SUDO_USER:" "$BACKUP_DIR" 2>/dev/null || true
  fi
}

etapa_instalar_robos() {
  title "3 · Robots, Indicators and Sets"
  require_root
  need_base || return 1
  criar_estrutura_robos

  echo "  Place the files in the correct folder and then run this option:"
  echo
  echo "    ${C_CYAN}$ROBOS_DIR/MT4/Experts${C_RESET}       ${C_DIM}MT4 robots (.ex4)${C_RESET}"
  echo "    ${C_CYAN}$ROBOS_DIR/MT4/Indicators${C_RESET}    ${C_DIM}MT4 indicators (.ex4)${C_RESET}"
  echo "    ${C_CYAN}$ROBOS_DIR/MT5/Experts${C_RESET}       ${C_DIM}MT5 robots (.ex5)${C_RESET}"
  echo "    ${C_CYAN}$ROBOS_DIR/MT5/Indicators${C_RESET}    ${C_DIM}MT5 indicators (.ex5)${C_RESET}"
  echo "    ${C_CYAN}$ROBOS_DIR/sets${C_RESET}              ${C_DIM}.set files (MT4 and MT5 in the same folder)${C_RESET}"
  echo
  echo "  ${C_DIM}From your PC: scp -P $SSH_PORT MyRobot.ex5 root@$(server_ip):$ROBOS_DIR/MT5/Experts/${C_RESET}"
  echo

  local f resto
  # warnings: file in the wrong place
  while IFS= read -r -d '' f; do
    warn "ignored (MT5 extension in MT4 folder): ${f#"$ROBOS_DIR"/}"
  done < <(find "$ROBOS_DIR/MT4" -maxdepth 2 -type f \( -iname '*.ex5' -o -iname '*.mq5' \) -print0 2>/dev/null)
  while IFS= read -r -d '' f; do
    warn "ignored (MT4 extension in MT5 folder): ${f#"$ROBOS_DIR"/}"
  done < <(find "$ROBOS_DIR/MT5" -maxdepth 2 -type f \( -iname '*.ex4' -o -iname '*.mq4' \) -print0 2>/dev/null)
  while IFS= read -r -d '' f; do
    warn "loose in root (move to MT4/ or MT5/): $(basename "$f")"
  done < <(find "$ROBOS_DIR" -maxdepth 1 -type f \( -iname '*.ex4' -o -iname '*.ex5' -o -iname '*.mq4' -o -iname '*.mq5' \) -print0 2>/dev/null)

  local id kind src destino base novo_set=0
  local -a pats files
  local total=0 novos=0 iguais=0 pendentes=0 deixados=0
  for id in mt4 mt5; do
    if [[ "$id" == "mt4" ]]; then
      pats=(\( -iname '*.ex4' -o -iname '*.mq4' \))
    else
      pats=(\( -iname '*.ex5' -o -iname '*.mq5' \))
    fi
    for kind in Experts Indicators; do
      src="$ROBOS_DIR/${id^^}/$kind"
      files=()
      while IFS= read -r -d '' f; do files+=("$f"); done \
        < <(find "$src" -maxdepth 1 -type f "${pats[@]}" -print0 2>/dev/null | sort -z)
      ((${#files[@]} > 0)) || continue
      total=$((total + ${#files[@]}))

      destino="$(mql_dest "$id" "$kind" || true)"
      if [[ -z "$destino" ]]; then
        err "${id^^}/$kind: ${#files[@]} file(s) waiting, but ${id^^} is not installed (option 2)."
        pendentes=$((pendentes + ${#files[@]}))
        continue
      fi
      for f in "${files[@]}"; do
        base="$(basename "$f")"
        if [[ -f "$destino/$base" ]] && cmp -s "$f" "$destino/$base"; then
          iguais=$((iguais + 1))
          continue
        fi
        if cp -f "$f" "$destino/$base"; then
          chown 1000:1000 "$destino/$base"; chmod 644 "$destino/$base"
          ok "$base ${S_ARR} ${id^^}/$kind"
          novos=$((novos + 1))
        else
          err "failed to copy $base"
        fi
      done
    done
  done

  # ---- Sets (.set): single folder; asks which terminal the first time ----
  # Choice is stored in sets/.destinos; subsequent runs copy without asking.
  local memo="$ROBOS_DIR/sets/.destinos" alvo resp
  local -a sets=()
  while IFS= read -r -d '' f; do sets+=("$f"); done \
    < <(find "$ROBOS_DIR/sets" -maxdepth 1 -type f -iname '*.set' -print0 2>/dev/null | sort -z)
  for f in "${sets[@]}"; do
    base="$(basename "$f")"
    total=$((total + 1))
    alvo=""
    [[ -f "$memo" ]] && alvo="$(awk -F'|' -v n="$base" '$1==n{print $2; exit}' "$memo")"
    if [[ -z "$alvo" ]]; then
      echo
      echo "  ${C_BOLD}$base${C_RESET} ${C_DIM}(new set)${C_RESET}"
      echo "    1) MT4    2) MT5    0) Leave as is"
      read -rp "    Which terminal? [0-2]: " resp || true
      case "${resp:-0}" in
        1) alvo="mt4" ;;
        2) alvo="mt5" ;;
        *) info "  left in sets/: $base"; deixados=$((deixados + 1)); continue ;;
      esac
      novo_set=1
    else
      novo_set=0
    fi
    destino="$(mql_dest "$alvo" Presets || true)"
    if [[ -z "$destino" ]]; then
      err "$base: ${alvo^^} is not installed yet (option 2)."
      pendentes=$((pendentes + 1))
      continue
    fi
    if [[ -f "$destino/$base" ]] && cmp -s "$f" "$destino/$base"; then
      iguais=$((iguais + 1))
    elif cp -f "$f" "$destino/$base"; then
      chown 1000:1000 "$destino/$base"; chmod 644 "$destino/$base"
      ok "$base ${S_ARR} ${alvo^^}/Presets"
      novos=$((novos + 1))
    else
      err "failed to copy $base"
      continue
    fi
    (( novo_set )) && printf '%s|%s\n' "$base" "$alvo" >> "$memo"
  done

  echo
  if (( total == 0 )); then
    warn "No files found in the folders above."
    return 0
  fi
  info "$total file(s) in folders: $novos new/updated, $iguais already identical, $pendentes pending, $deixados left in sets/."
  if (( novos > 0 )); then
    if container_running && confirm "Restart MT4/MT5 so the Navigator picks up the new files?"; then
      dc exec -T mt mt-sv restart mt4 >/dev/null 2>&1 || true
      dc exec -T mt mt-sv restart mt5 >/dev/null 2>&1 || true
      ok "Terminals restarted (those that are installed)"
    fi
    echo
    echo "  ${C_DIM}In MetaTrader: Navigator → Expert Advisors / Indicators (or right-click → Refresh).${C_RESET}"
    echo "  ${C_DIM}Remember to enable \"Algo Trading\" / \"Allow automated trading\" in the terminal.${C_RESET}"
  fi
}

# -----------------------------------------------------------------------------
# Step 4 — Status / Diagnostics
# -----------------------------------------------------------------------------
etapa_status() {
  title "4 · Status and diagnostics"
  require_root
  need_base || return 1
  local cn; cn="$(container_name)"

  echo "  ${C_BOLD}Container${C_RESET}"; rule 30
  dc ps 2>&1 | sed 's/^/  /' || true
  echo

  if container_running; then
    echo "  ${C_BOLD}Internal services (supervisord)${C_RESET}"; rule 30
    dc exec -T mt mt-sv status 2>/dev/null | sed 's/^/  /' || warn "could not query supervisord"
    echo
    echo "  ${C_BOLD}Terminal processes${C_RESET}"; rule 30
    dc exec -T mt ps aux 2>/dev/null | grep -E 'terminal(64)?\.exe' | grep -v grep | cut -c1-$((COLS - 2)) | sed 's/^/  /' \
      || echo "  (no terminal running)"
    echo
    echo "  ${C_BOLD}Resources${C_RESET}"; rule 30
    docker stats --no-stream --format '  CPU {{.CPUPerc}}   RAM {{.MemUsage}} ({{.MemPerc}})   PIDs {{.PIDs}}' "$cn" 2>/dev/null || true
    free -m | awk 'NR==1||/Mem|Swap/' | sed 's/^/  /'
    df -h "$APP_DIR" | awk 'NR==2{print "  Disk: " $3 " used of " $2 " (" $5 ")"}'
    echo
    echo "  ${C_BOLD}Last log lines${C_RESET}"; rule 30
    dc exec -T mt tail -8 /home/mt/logs/mt-docker.log 2>/dev/null | cut -c1-$((COLS - 2)) | sed 's/^/  /' || true
  else
    warn "Container is not running (menu 5 → Start)."
  fi
  echo
  mostrar_acesso
}

# -----------------------------------------------------------------------------
# Step 5 — Operations
# -----------------------------------------------------------------------------
etapa_operacao() {
  need_base || { pause; return; }
  local op
  while true; do
    title "5 · Operations"
    painel; echo
    echo "    1) Restart the whole container"
    echo "    2) Stop the container"
    echo "    3) Start the container"
    echo "    4) Restart MT4        5) Restart MT5"
    echo "    6) Stop MT4           7) Stop MT5"
    echo "    8) Start MT4          9) Start MT5"
    echo "    0) Back"
    echo
    read -rp "  Option [0-9]: " op || { echo; continue; }
    case "$op" in
      1) confirm "Restart the whole container?" && { dc restart >/dev/null 2>&1 && ok "container restarted" || err "failed"; } ;;
      2) confirm "Stop the container (terminals will close)?" && { dc stop >/dev/null 2>&1 && ok "container stopped" || err "failed"; } ;;
      3) dc start >/dev/null 2>&1 && ok "container started" || err "failed" ;;
      4) dc exec -T mt mt-sv restart mt4 2>&1 | sed 's/^/  /' ;;
      5) dc exec -T mt mt-sv restart mt5 2>&1 | sed 's/^/  /' ;;
      6) dc exec -T mt mt-sv stop mt4 2>&1 | sed 's/^/  /' ;;
      7) dc exec -T mt mt-sv stop mt5 2>&1 | sed 's/^/  /' ;;
      8) dc exec -T mt mt-sv start mt4 2>&1 | sed 's/^/  /' ;;
      9) dc exec -T mt mt-sv start mt5 2>&1 | sed 's/^/  /' ;;
      0) return ;;
      *) warn "invalid option" ;;
    esac
    pause
  done
}

# -----------------------------------------------------------------------------
# Step 6 — Maintenance
# -----------------------------------------------------------------------------
fazer_backup() {
  run_spin "Creating backup" "$APP_DIR/data/logs/host-backup.log" bash "$APP_DIR/scripts/backup.sh" || return 1
  ls -1t "$BACKUP_DIR"/mt-backup-*.tar.gz 2>/dev/null | head -3 | while read -r b; do
    echo "    ${C_DIM}$(du -h "$b" | cut -f1)  $b${C_RESET}"
  done
  echo "  ${C_DIM}Folder: $BACKUP_DIR ($(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1) total; nothing is deleted automatically)${C_RESET}"
}

restaurar_backup() {
  local bks=() b i=1 n
  while IFS= read -r b; do bks+=("$b"); done < <(ls -1t "$BACKUP_DIR"/mt-backup-*.tar.gz 2>/dev/null)
  if ((${#bks[@]} == 0)); then warn "No backups in $BACKUP_DIR"; return 0; fi
  echo "  ${C_BOLD}Available backups:${C_RESET}"
  for b in "${bks[@]}"; do
    printf '    %2d) %s  %s(%s)%s\n' "$i" "$(basename "$b")" "$C_DIM" "$(du -h "$b" | cut -f1)" "$C_RESET"
    i=$((i + 1))
  done
  read -rp "  Restore which? [1-${#bks[@]}, 0=cancel]: " n || true
  if ! [[ "${n:-0}" =~ ^[0-9]+$ ]] || (( n < 1 || n > ${#bks[@]} )); then info "cancelled"; return 0; fi
  b="${bks[n-1]}"
  warn "This REPLACES current MT4/MT5 data (accounts, EAs, settings) with the backup contents."
  confirm "Confirm restore of $(basename "$b")?" || { info "cancelled"; return 0; }

  dc stop >/dev/null 2>&1 || true
  local p
  for p in prefix-mt4 prefix-mt5; do
    if tar -tzf "$b" 2>/dev/null | grep -q "^$p/drive_c"; then
      rm -rf "$APP_DIR/data/$p/drive_c"
    fi
  done
  if tar -C "$APP_DIR/data" -xzf "$b"; then
    chown -R 1000:1000 "$APP_DIR/data"
    chmod 700 "$APP_DIR/data/prefix-mt4" "$APP_DIR/data/prefix-mt5" 2>/dev/null
    ok "Backup restored"
  else
    err "failed to extract backup"
  fi
  dc start >/dev/null 2>&1 && ok "container started"
}

trocar_senha_vnc() {
  local pw
  read -rsp "  New VNC password (min. 8; only the first 8 characters are used): " pw || true; echo
  if (( ${#pw} < 8 )); then err "password too short"; return 1; fi
  pw="${pw:0:8}"
  env_set VNC_PASSWORD "$pw"
  info "Recreating container to apply..."
  dc up -d --force-recreate >/dev/null 2>&1 && ok "Password changed" || err "failed to recreate"
}

desinstalar() {
  warn "This removes the container and image. Your data is only deleted if you ask."
  confirm "Continue with uninstall?" || { info "cancelled"; return 0; }
  dc down --rmi local >/dev/null 2>&1 && ok "container and image removed"
  if command -v crontab >/dev/null 2>&1; then
    local resto
    resto="$(crontab -l 2>/dev/null | grep -vF '# mt-docker-log-cleanup' || true)"
    if [[ -n "${resto//[[:space:]]/}" ]]; then
      printf '%s\n' "$resto" | crontab - 2>/dev/null || true
    else
      crontab -r 2>/dev/null || true
    fi
  fi
  rm -f "$MENU_BIN"
  echo
  echo "  Account data remains in: ${C_CYAN}$APP_DIR${C_RESET}"
  echo "  Robots and backups stay in ${C_CYAN}$ROBOS_DIR${C_RESET} and ${C_CYAN}$BACKUP_DIR${C_RESET} (not deleted)."
  local t; read -rp "  To DELETE EVERYTHING type DELETE (Enter keeps data): " t || true
  if [[ "${t:-}" == "DELETE" ]]; then
    rm -rf "${APP_DIR:?}" && ok "$APP_DIR deleted"
  else
    info "data kept"
  fi
}

etapa_manutencao() {
  need_base || { pause; return; }
  local op
  while true; do
    title "6 · Maintenance"
    echo "    1) Backup now"
    echo "    2) Restore a backup"
    echo "    3) Update (backup + rebuild image)"
    echo "    4) Live logs (Ctrl+C to return)"
    echo "    5) Live resource usage (Ctrl+C to return)"
    echo "    6) Change VNC password"
    echo "    7) Change timezone"
    echo "    8) Uninstall"
    echo "    0) Back"
    echo
    read -rp "  Option [0-8]: " op || { echo; continue; }
    case "$op" in
      1) fazer_backup ;;
      2) restaurar_backup ;;
      3) if confirm "Backup, rebuild image and restart?"; then
           run_spin "Updating" "$APP_DIR/data/logs/host-update.log" bash "$APP_DIR/scripts/update.sh"
         fi ;;
      4) dc logs -f --tail 50 mt ;;
      5) docker stats "$(container_name)" ;;
      6) trocar_senha_vnc ;;
      7) escolher_tz && confirm "Restart container to apply the new timezone?" && dc up -d --force-recreate >/dev/null 2>&1 && ok "applied" ;;
      8) desinstalar; [[ -d "$APP_DIR" ]] || return ;;
      0) return ;;
      *) warn "invalid option" ;;
    esac
    pause
  done
}

etapa_acesso() {
  title "7 · How to access"
  need_base || return 1
  mostrar_acesso
}

# -----------------------------------------------------------------------------
# Guided installation (everything in sequence)
# -----------------------------------------------------------------------------
etapa_guiada() {
  title "A · Guided installation"
  echo "  I will run, in order: ${C_BOLD}base → MT4/MT5 → robots${C_RESET}."
  echo "  Estimated total time: 30–60 min (most of it is automatic)."
  echo
  confirm "Start?" || return 0
  etapa_instalar_base || { err "Base failed; aborting."; return 1; }
  echo; read -rp "  ENTER to continue to MT4/MT5..." _ || true
  etapa_instalar_terminais
  echo; read -rp "  ENTER to continue to robots/indicators..." _ || true
  etapa_instalar_robos
  echo
  ok "${C_BOLD}All done.${C_RESET} Use ${C_CYAN}sudo mt-menu${C_RESET} whenever you want to come back."
}

# -----------------------------------------------------------------------------
# Main menu
# -----------------------------------------------------------------------------
run_etapa() {
  "$@"
  pause
}

menu() {
  local opt
  while true; do
    clear 2>/dev/null || true
    echo
    echo "  ${C_BOLD}${C_CYAN}MetaTrader 4 + 5 in Docker · noVNC${C_RESET}"
    rule
    painel
    rule
    echo "  ${C_DIM}Robots: $ROBOS_DIR${C_RESET}"
    echo "  ${C_DIM}Backups: $BACKUP_DIR${C_RESET}"
    echo
    echo "   ${C_BOLD}A)${C_RESET} Guided installation ${C_DIM}(recommended first time)${C_RESET}"
    echo
    echo "   ${C_BOLD}1)${C_RESET} Install base              ${C_DIM}Docker, swap, image${C_RESET}"
    echo "   ${C_BOLD}2)${C_RESET} Install / remove MT4/5    ${C_DIM}install or uninstall${C_RESET}"
    echo "   ${C_BOLD}3)${C_RESET} Robots, Indicators & Sets ${C_DIM}.ex4 .ex5 .set${C_RESET}"
    echo "   ${C_BOLD}4)${C_RESET} Status and diagnostics"
    echo "   ${C_BOLD}5)${C_RESET} Operations                ${C_DIM}start / stop / restart${C_RESET}"
    echo "   ${C_BOLD}6)${C_RESET} Maintenance               ${C_DIM}backup, update, logs, password${C_RESET}"
    echo "   ${C_BOLD}7)${C_RESET} How to access             ${C_DIM}VNC password and SSH tunnel${C_RESET}"
    echo "   ${C_BOLD}0)${C_RESET} Exit"
    echo
    read -rp "  Choose [A,0-7]: " opt || { echo; continue; }
    case "${opt,,}" in
      a) run_etapa etapa_guiada ;;
      1) run_etapa etapa_instalar_base ;;
      2) run_etapa etapa_instalar_terminais ;;
      3) run_etapa etapa_instalar_robos ;;
      4) run_etapa etapa_status ;;
      5) etapa_operacao ;;
      6) etapa_manutencao ;;
      7) run_etapa etapa_acesso ;;
      0|q|exit|quit) echo; info "Goodbye."; exit 0 ;;
      "") ;;
      *) warn "invalid option"; sleep 1 ;;
    esac
  done
}

main() {
  require_root
  # keep the "mt-menu" shortcut always on the latest version of this script
  [[ -d "$APP_DIR/scripts" ]] && instalar_atalho
  criar_estrutura_robos
  case "${1:-menu}" in
    menu)      menu ;;
    guided|guiada) etapa_guiada ;;
    base)      etapa_instalar_base ;;
    terminals|terminais) etapa_instalar_terminais ;;
    robots|robos) etapa_instalar_robos ;;
    status)    etapa_status ;;
    backup)    need_base && fazer_backup ;;
    -h|--help|help|ajuda)
      sed -n '2,32p' "$SELF" | sed 's/^# \{0,1\}//' ;;
    *) die "unknown command: $1 (use: menu guided base terminals robots status backup)" ;;
  esac
}

# Allow "source" for testing without running the menu
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
