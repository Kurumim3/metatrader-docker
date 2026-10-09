#!/usr/bin/env bash
# =============================================================================
# Common Shared Library Functions for Wine & MetaTrader
# =============================================================================
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

die() { 
  log ERROR "$1" "${*:2}"
  exit 1
}

retry() {
  local n="$1" d="$2" i; shift 2
  for ((i = 1; i <= n; i++)); do
    if "$@"; then return 0; fi
    log WARN retry "Attempt $i/$n failed: $*"
    sleep $((d * i))
  done
  return 1
}

mem_limit_mb() {
  local v=max
  if   [[ -r /sys/fs/cgroup/memory.max ]]; then 
    v="$(</sys/fs/cgroup/memory.max)"
  elif [[ -r /sys/fs/cgroup/memory/memory.limit_in_bytes ]]; then 
    v="$(</sys/fs/cgroup/memory/memory.limit_in_bytes)"
  fi
  if [[ "$v" == "max" || ! "$v" =~ ^[0-9]+$ || ${#v} -gt 12 ]]; then
    awk '/^MemTotal:/{print int($2/1024)}' /proc/meminfo
  else
    echo $(( v / 1048576 ))
  fi
}

verify_installer() {
  local f="$1" size
  size="$(stat -c %s "$f")"
  (( size >= 200000 )) || die verify "Installer archive is too small (${size} bytes)"
  [[ "$(head -c2 "$f")" == "MZ" ]] || die verify "File header is not a valid Windows executable (MZ)"
  log INFO verify "Payload size: ${size}B verified"
}

load_terminal() {
  local default_deps="corefonts vcrun2019 winhttp gdiplus msxml6"
  case "${1:-}" in
    mt4)
      MT_ID=mt4
      MT_NAME="MetaTrader 4"
      MT_ARCH="${MT4_ARCH:-win32}"
      MT_EXE_NAME="terminal.exe"
      MT_URL="https://download.mql5.com/cdn/web/metaquotes.software.corp/mt4/mt4setup.exe"
      MT_DEPS="${EA_DEPS_MT4:-$default_deps}"
      ;;
    mt5)
      MT_ID=mt5
      MT_NAME="MetaTrader 5"
      MT_ARCH="win64"
      MT_EXE_NAME="terminal64.exe"
      MT_URL="https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe"
      MT_DEPS="${EA_DEPS_MT5:-$default_deps}"
      ;;
    *) 
      die lib "Invalid terminal target: '${1:-}'"
      ;;
  esac
  export WINEPREFIX="/home/mt/prefix/$MT_ID"
  export WINEARCH="$MT_ARCH"
  MT_MARKER="$WINEPREFIX/.mt_exe_path"
}

find_exe() {
  find "$WINEPREFIX/drive_c" -maxdepth 6 -type f -iname "$MT_EXE_NAME" \
       -not -ipath '*/windows/*' -print -quit 2>/dev/null
}
