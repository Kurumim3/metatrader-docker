#!/usr/bin/env bash
# =============================================================================
# install-mt-docker.sh — Instalador + Gerenciador MT4/MT5 em Docker com noVNC
# =============================================================================
# Menu interativo para VPS Ubuntu/Debian SEM interface gráfica (1-2 GB de RAM).
# Usa os instaladores OFICIAIS da MetaQuotes (não precisa configurar corretora).
#
# Uso:
#   sudo bash install-mt-docker.sh            # abre o menu
#   sudo bash install-mt-docker.sh guiada     # instalação guiada completa
#   sudo bash install-mt-docker.sh status     # status / diagnóstico
#   sudo bash install-mt-docker.sh backup     # backup agora
#
# Depois da primeira execução, o atalho  sudo mt-menu  fica disponível.
#
# Configuração (opcional):
#   Copie .env.example para .env se quiser customizar. O script carrega .env
#   automaticamente se existir em $APP_DIR ou ao lado do script.
#
#   APP_DIR=/opt/mt-docker   diretório base
#   SSH_PORT=22              porta SSH da VPS (para as mensagens)
#   WINE_VERSION=...         versão do Wine; padrão 10.0.0.0~jammy-1
#
# Robôs/Indicadores (pasta "robos" criada AO LADO do script, na primeira execução):
#   MT4/Experts  MT4/Indicators  (.ex4 / .mq4)
#   MT5/Experts  MT5/Indicators  (.ex5 / .mq5)
#   sets/                        (.set de MT4 e MT5; o menu pergunta o terminal)
#   Coloque os arquivos na pasta certa e use a opção 3 do menu.
#
# NOTA — Fins de linha (CRLF): se o arquivo veio do Windows, rode antes:
#     sed -i 's/\r$//' install-mt-docker.sh
# =============================================================================
set -uo pipefail
# (sem "set -e" no menu: um erro numa etapa volta ao menu em vez de fechar tudo.
#  Os scripts gerados para dentro do container usam set -e normalmente.)

# -----------------------------------------------------------------------------
# Configuração global
# -----------------------------------------------------------------------------
APP_DIR="${APP_DIR:-/opt/mt-docker}"

# Carrega .env (se existir) ANTES de ler as demais variáveis.
# Ordem de precedência: variáveis passadas na linha de comando > .env > defaults.
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

# Pastas "robos" e "backups": ficam AO LADO de onde o script foi executado (fácil de achar) e é
# lembrada em $APP_DIR/.robos_dir, para o atalho "mt-menu" usar a mesma pasta.
# Para trocar de lugar: defina ROBOS_DIR=/caminho e/ou BACKUP_DIR=/caminho ao rodar o script.
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
  # backups: no mesmo lugar (ao lado da pasta dos robôs), lembrado em .backup_dir
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
# Visual (terminal puro; cai para ASCII se o locale não for UTF-8)
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

badge() { # badge ok|warn|err|off "texto"
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
  [[ $EUID -eq 0 ]] || die "execute como root: sudo bash $SELF"
}

pause() {
  echo
  read -rp "  ${C_DIM}ENTER para voltar...${C_RESET} " _ || true
}

confirm() {
  local ans
  read -rp "  $1 [s/N] " ans || true
  ans="${ans,,}"
  [[ "$ans" == "s" || "$ans" == "sim" || "$ans" == "y" || "$ans" == "yes" ]]
}

# Ctrl+C não fecha o menu: só interrompe a tarefa atual
trap 'echo' INT
trap 'tput cnorm 2>/dev/null || true' EXIT

# Executa um comando em segundo plano mostrando spinner, tempo e a última linha do log.
# uso: run_spin "mensagem" /caminho/log comando args...
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
    err "$msg falhou (código $rc). Últimas linhas do log:"
    tail -n 15 "$logf" 2>/dev/null | sed 's/^/      /' >&2
    echo "      ${C_DIM}log completo: $logf${C_RESET}" >&2
  fi
  return "$rc"
}

# -----------------------------------------------------------------------------
# Utilidades
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
  printf '%s' "${ip:-IP_DA_VPS}"
}

env_get() { # env_get CHAVE
  [[ -f "$ENV_FILE" ]] || return 0
  grep -E "^$1=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | sed -e 's/^"//' -e 's/"$//'
}

env_set() { # env_set CHAVE VALOR  (seguro para qualquer caractere)
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
    err "Base ainda não instalada. Use a opção 1 (ou A) primeiro."
    return 1
  fi
}

# Espera o supervisord do container responder (basta o socket existir)
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
    printf '\r  %s aguardando healthcheck... %s (%ds)  ' "${SPIN[i % ${#SPIN[@]}]}" "$st" $((i * 5))
    sleep 5
  done
  printf '\r\033[K'
  return 1
}

# Estado de um terminal para o painel
term_state() { # term_state mt4|mt5
  local id="$1" marker="$APP_DIR/data/prefix-${1}/.mt_exe_path"
  if [[ ! -s "$marker" ]]; then
    badge off "${id^^} não instalado"; return
  fi
  if container_running; then
    local line
    line="$(dc exec -T mt mt-sv status "$id" 2>/dev/null | head -1 || true)"
    case "$line" in
      *RUNNING*)  badge ok  "${id^^} rodando" ;;
      *STARTING*) badge warn "${id^^} iniciando" ;;
      *)          badge err "${id^^} parado" ;;
    esac
  else
    badge off "${id^^} instalado (container parado)"
  fi
}

painel() {
  local d c mem
  if command -v docker >/dev/null 2>&1; then d="$(badge ok "Docker")"; else d="$(badge off "Docker ausente")"; fi
  if [[ ! -f "$COMPOSE_FILE" ]]; then
    c="$(badge off "base não instalada")"
  elif container_running; then
    local st; st="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$(container_name)" 2>/dev/null || echo ?)"
    case "$st" in
      healthy)  c="$(badge ok "container saudável")" ;;
      starting) c="$(badge warn "container iniciando")" ;;
      *)        c="$(badge warn "container: $st")" ;;
    esac
  else
    c="$(badge err "container parado")"
  fi
  mem="$(awk '/^MemTotal:/{t=$2}/^MemAvailable:/{a=$2}END{printf "%d/%d MB livres", a/1024, t/1024}' /proc/meminfo)"
  echo "  $d    $c    ${C_DIM}RAM $mem${C_RESET}"
  if [[ -f "$COMPOSE_FILE" ]]; then
    echo "  $(term_state mt4)    $(term_state mt5)"
  fi
}

# -----------------------------------------------------------------------------
# Informações de acesso
# -----------------------------------------------------------------------------
mostrar_acesso() {
  local pw cn tz ip
  pw="$(env_get VNC_PASSWORD)"; pw="${pw:0:8}"; cn="$(container_name)"; tz="$(env_get TZ)"
  ip="$(server_ip)"
  echo "  ${C_BOLD}Acesso ao MetaTrader (noVNC)${C_RESET}"
  rule
  echo "  Container:   $cn"
  echo "  Fuso (TZ):   ${tz:-?}"
  echo "  Senha VNC:   ${C_YELLOW}${pw:-'(veja .env)'}${C_RESET}"
  echo
  echo "  O noVNC fica fechado para a internet (só 127.0.0.1). Para acessar,"
  echo "  abra um túnel SSH ${C_BOLD}no seu computador${C_RESET} (Windows/Mac/Linux):"
  echo
  echo "    ${C_CYAN}ssh -N -p $SSH_PORT -L 6080:127.0.0.1:6080 root@$ip${C_RESET}"
  echo
  echo "  e abra no navegador:"
  echo
  echo "    ${C_CYAN}http://localhost:6080/vnc.html?autoconnect=1&resize=scale${C_RESET}"
  echo
  echo "  ${C_DIM}Dica: o terminal do túnel precisa ficar aberto enquanto você usa o noVNC.${C_RESET}"
}

# -----------------------------------------------------------------------------
# Fuso horário
# -----------------------------------------------------------------------------
escolher_tz() {
  local atual opt chosen="America/Sao_Paulo"
  atual="$(env_get TZ)"; atual="${atual:-America/Sao_Paulo}"
  echo "  ${C_BOLD}Fuso horário do container${C_RESET} ${C_DIM}(atual: $atual)${C_RESET}"
  echo "    1) America/Sao_Paulo  (padrão BR)"
  echo "    2) UTC"
  echo "    3) Usar o da máquina"
  echo "    4) Outro (digitar, ex: Europe/London)"
  echo "    5) Manter o atual"
  read -rp "  Opção [1-5] (Enter=5): " opt || true
  case "${opt:-5}" in
    1) chosen="America/Sao_Paulo" ;;
    2) chosen="UTC" ;;
    3)
      if [[ -f /etc/timezone ]]; then chosen="$(tr -d '[:space:]' < /etc/timezone)"
      elif command -v timedatectl >/dev/null 2>&1; then chosen="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
      fi
      chosen="${chosen:-America/Sao_Paulo}" ;;
    4)
      read -rp "  Digite o TZ: " chosen || true
      chosen="${chosen:-$atual}" ;;
    *) chosen="$atual" ;;
  esac
  if [[ ! -e "/usr/share/zoneinfo/$chosen" && "$chosen" != "UTC" ]]; then
    warn "TZ '$chosen' não existe em /usr/share/zoneinfo; mantendo $atual"
    chosen="$atual"
  fi
  env_set TZ "$chosen"
  ok "TZ=$chosen"
}

# -----------------------------------------------------------------------------
# Versão do Wine
# -----------------------------------------------------------------------------
escolher_wine() {
  local atual def=1 opt v
  atual="$(env_get WINE_VERSION)"; atual="${atual:-10.0.0.0~jammy-1}"
  [[ "$atual" == 11.* ]] && def=2
  echo "  ${C_BOLD}Versão do Wine${C_RESET} ${C_DIM}(atual: ${atual%%.*})${C_RESET}"
  echo "    1) Wine 10  ${C_GREEN}(recomendado)${C_RESET}  ${C_DIM}— funciona com o instalador oficial da MetaQuotes${C_RESET}"
  echo "    2) Wine 11  ${C_DIM}— mais novo; o instalador oficial da MetaQuotes pode falhar${C_RESET}"
  read -rp "  Opção [1-2] (Enter=$def): " opt || true
  case "${opt:-$def}" in
    2) v="11.0.0.0~jammy-1" ;;
    *) v="10.0.0.0~jammy-1" ;;
  esac
  env_set WINE_VERSION "$v"
  ok "Wine ${v%%.*} (WINE_VERSION=$v)"
}

# -----------------------------------------------------------------------------
# Geração dos arquivos do projeto
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
# Versão do Wine fixada: o instalador oficial da MetaQuotes falha no Wine 11
# ("A debugger has been found running"). Vazio = sempre a mais recente.
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
      VNC_PASSWORD: "${VNC_PASSWORD:?VNC_PASSWORD não definida; rode scripts/setup-host.sh}"
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
    log WARN retry "tentativa $i/$n falhou: $*"
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
    *) die lib "terminal inválido: '${1:-}'" ;;
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

log INFO "$COMP" "iniciando (uid=$(id -u))"

for d in /home/mt/prefix/mt4 /home/mt/prefix/mt5 /home/mt/logs; do  [[ -w "$d" ]] || die "$COMP" "sem permissão em $d. No host: chown -R 1000:1000 /opt/mt-docker/data"
done

[[ -n "${VNC_PASSWORD:-}" ]] || die "$COMP" "VNC_PASSWORD vazia. Rode scripts/setup-host.sh"
(( ${#VNC_PASSWORD} >= 8 )) || die "$COMP" "VNC_PASSWORD precisa de pelo menos 8 caracteres"
if (( ${#VNC_PASSWORD} > 8 )); then
  log WARN "$COMP" "VNC_PASSWORD tem ${#VNC_PASSWORD} chars; x11vnc usa só os 8 primeiros"
  VNC_PASSWORD="${VNC_PASSWORD:0:8}"
fi
( umask 077; printf '%s\n' "$VNC_PASSWORD" > /tmp/vnc.pass )
unset VNC_PASSWORD

rm -f /tmp/.X99-lock /tmp/.X11-unix/X99 /tmp/supervisor.sock /tmp/supervisord.pid

LIMIT="$(mem_limit_mb)"
log INFO "$COMP" "limite de memória efetivo: ${LIMIT}MB"
(( LIMIT >= 700 )) || log WARN "$COMP" "memória < 700MB: MT5 + Wine podem sofrer OOM"

export RESOLUTION="${RESOLUTION:-1024x600x16}"
log INFO "$COMP" "iniciando supervisord (resolução $RESOLUTION)"
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

ID="${1:?uso: run-terminal mt4|mt5}"
load_terminal "$ID"
COMP="run-$ID"
WPID=""

stop() {
  log INFO "$COMP" "SIGTERM recebido: encerrando $MT_NAME com graça"
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
    log WARN "$COMP" "$MT_NAME não instalado. Rode: docker compose exec mt mt-install $ID"
  fi
  n=$((n + 1))
  sleep 10 & wait $!
done

EXE="$(<"$MT_MARKER")"
[[ -f "$EXE" ]] || die "$COMP" "executável não existe: $EXE (reinstale: mt-install $ID --force)"

log INFO "$COMP" "iniciando $MT_NAME: $EXE"
cd "$(dirname "$EXE")"
wine "$EXE" /portable &
WPID=$!

rc=0
wait "$WPID" || rc=$?
log WARN "$COMP" "$MT_NAME encerrou (rc=$rc); supervisor vai reiniciar"
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
Uso: mt-install mt4|mt5 [--force] [--skip-deps] [--installer CAMINHO]
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
    *) usage; die "$COMP" "opção desconhecida: $1" ;;
  esac
  shift
done

load_terminal "$ID"

RUNFLAG=/tmp/mt-install.running
if [[ -f "$RUNFLAG" ]] && kill -0 "$(cat "$RUNFLAG")" 2>/dev/null; then
  die "$COMP" "outra instalação em andamento"
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
trap 'log ERROR "$COMP" "falha na linha $LINENO"' ERR

LIMIT="$(mem_limit_mb)"
(( LIMIT >= 600 )) || die "$COMP" "limite de memória (${LIMIT}MB) < 600MB"
xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 || die "$COMP" "display $DISPLAY indisponível"

if [[ -s "$MT_MARKER" && $FORCE -eq 0 ]]; then
  log INFO "$COMP" "$MT_NAME já instalado: nada a fazer"
  exit 0
fi
if (( FORCE )) && pgrep -fi "$MT_EXE_NAME" >/dev/null; then
  die "$COMP" "$MT_NAME em execução. Pare: mt-sv stop $ID"
fi
if (( FORCE )); then rm -f "$MT_MARKER"; fi

if [[ ! -f "$WINEPREFIX/.mt_prefix_ready" ]]; then
  log INFO "$COMP" "criando prefixo $MT_ARCH"
  WINEDLLOVERRIDES="mscoree,mshtml=d;winemenubuilder.exe=d" timeout 300 wineboot --init
  WINEPREFIX="$WINEPREFIX" wineserver -w
  touch "$WINEPREFIX/.mt_prefix_ready"
fi

if (( SKIP_DEPS == 0 )); then
  mkdir -p "$WINEPREFIX/.deps"
  failed=()
  for dep in $MT_DEPS; do
    if [[ -f "$WINEPREFIX/.deps/$dep" ]]; then
      log INFO deps "$dep já instalado"; continue
    fi
    log INFO deps "instalando $dep"
    if retry 2 10 timeout 2400 winetricks -q "$dep"; then
      touch "$WINEPREFIX/.deps/$dep"
    else
      failed+=("$dep")
      log ERROR deps "falhou: $dep"
      log WARN deps "se a URL da Microsoft mudou, tente atualizar WINETRICKS_VERSION no Dockerfile"
    fi
    WINEPREFIX="$WINEPREFIX" wineserver -w || true
  done
  if [[ ! -f "$WINEPREFIX/.deps/win10" ]]; then
    if winetricks -q win10; then touch "$WINEPREFIX/.deps/win10"; fi
    WINEPREFIX="$WINEPREFIX" wineserver -w || true
  fi
  if ((${#failed[@]} > 0)); then
    log WARN deps "falharam: ${failed[*]}"
  fi
fi

if [[ -n "$LOCAL_INSTALLER" ]]; then
  [[ -f "$LOCAL_INSTALLER" ]] || die "$COMP" "instalador não encontrado: $LOCAL_INSTALLER"
  cp "$LOCAL_INSTALLER" "$INSTALLER"
else
  log INFO "$COMP" "baixando $MT_URL"
  retry 3 5 wget --timeout=30 --tries=1 -q -O "$INSTALLER" "$MT_URL" || die "$COMP" "download falhou"
fi
size="$(stat -c %s "$INSTALLER")"
(( size >= 200000 )) || die "$COMP" "instalador pequeno demais (${size} bytes)"
[[ "$(head -c2 "$INSTALLER")" == "MZ" ]] || die "$COMP" "cabeçalho não é executável Windows (MZ)"

log INFO "$COMP" "executando instalador (acompanhe pelo noVNC)"
timeout 900 wine "$INSTALLER" /auto >> "$LOG_DIR/setup-$ID.log" 2>&1 &
SETUP_PID=$!
terminal_seen=0
for ((i = 0; i < 180; i++)); do
  if pgrep -fi "$MT_EXE_NAME" >/dev/null; then
    log INFO "$COMP" "terminal iniciou; aguardando 90s para extração MQL/bases"
    sleep 90
    terminal_seen=1
    break
  fi
  if ! kill -0 "$SETUP_PID" 2>/dev/null; then
    log INFO "$COMP" "instalador encerrou; aguardando terminal por até 60s"
    for ((j = 0; j < 12; j++)); do
      if pgrep -fi "$MT_EXE_NAME" >/dev/null; then
        log INFO "$COMP" "terminal iniciou; aguardando 90s para extração MQL/bases"
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
(( terminal_seen )) || log WARN "$COMP" "terminal não detectado no prazo"

if kill -0 "$SETUP_PID" 2>/dev/null; then
  kill -TERM "$SETUP_PID" 2>/dev/null || true
  sleep 3
  wait "$SETUP_PID" 2>/dev/null || true
fi

EXE="$(find_exe || true)"
if [[ -z "$EXE" ]]; then
  find "$WINEPREFIX/drive_c" -iname 'terminal*.exe' 2>/dev/null | head -20 >> "$LOG_DIR/setup-$ID.log" || true
  die "$COMP" "$MT_EXE_NAME não encontrado (veja $LOG_DIR/setup-$ID.log)"
fi

if pgrep -fi "$MT_EXE_NAME" >/dev/null; then
  log INFO "$COMP" "fechando terminal órfão para entrega ao supervisor"
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
log INFO "$COMP" "$MT_NAME instalado: $EXE"
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

[[ $EUID -eq 0 ]] || die "execute como root: sudo $0"
command -v docker >/dev/null 2>&1 || die "Docker não encontrado"
docker compose version >/dev/null 2>&1 || die "Docker Compose v2 não encontrado"

TOTAL_MB="$(awk '/^MemTotal:/{print int($2/1024)}' /proc/meminfo)"
SWAP_MB="$(awk '/^SwapTotal:/{print int($2/1024)}' /proc/meminfo)"
AVAIL_MB="$(awk '/^MemAvailable:/{print int($2/1024)}' /proc/meminfo)"
CORES="$(nproc)"
if   (( TOTAL_MB <= 2048 )); then SWAP_TARGET=2048
elif (( TOTAL_MB <= 4096 )); then SWAP_TARGET=1024
else SWAP_TARGET=0; fi
log INFO "RAM=${TOTAL_MB}MB available=${AVAIL_MB}MB swap=${SWAP_MB}MB cpus=${CORES}"

if (( AVAIL_MB < 800 )); then
  log WARN "MemAvailable=${AVAIL_MB}MB < 800MB: VPS sobrecarregada agora; container pode iniciar lento ou sofrer OOM temporário"
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
    log WARN "/swapfile já está ativo mas é pequeno (${SWAP_MB}MB); não vou recriá-lo em uso"
  else
    log INFO "criando swap de ${NEED}MB"
    [[ -f /swapfile ]] || make_swapfile "$NEED"
    if ! swapon /swapfile 2>/dev/null; then
      make_swapfile "$NEED"
      swapon /swapfile 2>/dev/null || log WARN "swapon falhou (OpenVZ/LXC?)"
    fi
    grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    SWAP_MB="$(awk '/^SwapTotal:/{print int($2/1024)}' /proc/meminfo)"
  fi
fi

cat > /etc/sysctl.d/99-mt-docker.conf <<'SYS'
vm.swappiness=20
vm.vfs_cache_pressure=50
SYS
sysctl -q -p /etc/sysctl.d/99-mt-docker.conf >/dev/null 2>&1 || log WARN "sysctl não aplicado"

RESERVE=$(( TOTAL_MB * 15 / 100 )); (( RESERVE >= 200 )) || RESERVE=200
MEM_MB=$(( TOTAL_MB - RESERVE ))
(( MEM_MB >= 600 )) || log WARN "só ${MEM_MB}MB para o container"
SWAP_ALLOW=$(( SWAP_MB > 2048 ? 2048 : SWAP_MB ))
if (( SWAP_ALLOW == 0 )); then
  SWAP_ALLOW=512
  log WARN "host sem swap; memswap_limit usará +512 MB de headroom"
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
# win32 quebra instaladores de 64 bits ("Bad EXE format"); win64 roda os dois
[[ "$(get_kv MT4_ARCH)" == "win32" ]] && set_kv MT4_ARCH win64

if [[ -z "$(get_kv VNC_PASSWORD)" ]]; then
  PW="$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | cut -c1-8)"
  set_kv VNC_PASSWORD "$PW"
  log INFO "senha VNC gerada: $PW (ANOTE AGORA)"
else
  log INFO "senha VNC existente preservada"
fi

# Limpeza diária: logs antigos (>15 dias) e logs gigantes (>50MB) são truncados
CRON_MARKER="# mt-docker-log-cleanup"
CRON_CMD="0 3 * * * find ${APP_DIR}/data -type f -name '*.log' -mtime +15 -delete; find ${APP_DIR}/data/logs -type f -name '*.log' -size +50M -exec truncate -s 0 {} + ${CRON_MARKER}"
if command -v crontab >/dev/null 2>&1; then
  { crontab -l 2>/dev/null | grep -vF "$CRON_MARKER" || true; echo "$CRON_CMD"; } | crontab -
  log INFO "cron de limpeza de logs instalado/atualizado (diário 03:00)"
else
  log WARN "crontab não disponível; limpeza automática de logs não configurada"
fi

log INFO "limites: mem=${MEM_MB}m memswap=${MEMSWAP_MB}m cpus=${CPUS} shm=${SHM}m"
log INFO "pronto"
EOF

  cat > "$APP_DIR/scripts/backup.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
# Pasta: BACKUP_DIR > arquivo .backup_dir (gravado pelo menu) > $ROOT/backups
# BACKUP_KEEP=N mantém só os N mais recentes; padrão 0 = não apaga nada (apague à mão).
KEEP="${BACKUP_KEEP:-0}"
DEST="${BACKUP_DIR:-}"
if [[ -z "$DEST" && -s "$ROOT/.backup_dir" ]]; then DEST="$(<"$ROOT/.backup_dir")"; fi
DEST="${DEST:-$ROOT/backups}"
mkdir -p "$DEST"
TS="$(date +%Y%m%d-%H%M%S)"
OUT="$DEST/mt-backup-$TS.tar.gz"
log() { echo "$(date '+%Y-%m-%dT%H:%M:%S%z') [$1] [backup] ${*:2}"; }

NEED="$(du -sm data 2>/dev/null | cut -f1 || echo 0)"; FREE="$(df -Pm "$DEST" | awk 'NR==2{print $4}')"
(( FREE > NEED / 2 )) || { log ERROR "espaço insuficiente"; exit 1; }

# drive_c (terminal, conta, EAs) + registro do Wine + marcadores do instalador,
# para o backup restaurar um terminal completo mesmo depois de desinstalado.
TARGETS=()
for p in prefix-mt4 prefix-mt5; do
  [[ -d "data/$p/drive_c" ]] || continue
  TARGETS+=("$p/drive_c")
  for extra in system.reg user.reg userdef.reg .mt_exe_path .mt_prefix_ready .deps dosdevices; do
    if [[ -e "data/$p/$extra" || -L "data/$p/$extra" ]]; then TARGETS+=("$p/$extra"); fi
  done
done
if ((${#TARGETS[@]} == 0)); then
  log WARN "nenhum prefixo encontrado; backup ignorado"
  exit 0
fi

umask 077
log INFO "backup → $OUT (${TARGETS[*]})"
rc=0
tar -C data -czf "$OUT" \
    --exclude='Tester' --exclude='tester' \
    --ignore-failed-read \
    "${TARGETS[@]}" 2>/dev/null || rc=$?
if (( rc == 1 )); then log WARN "arquivos mudaram durante a cópia"; rc=0; fi
(( rc == 0 )) || { log ERROR "tar falhou"; rm -f "$OUT"; exit "$rc"; }

chown 1000:1000 "$OUT" 2>/dev/null || true
chmod 600 "$OUT"
log INFO "ok: $(du -h "$OUT" | cut -f1)  $OUT"
if (( KEEP > 0 )); then
  ls -1t "$DEST"/mt-backup-*.tar.gz 2>/dev/null | tail -n +"$((KEEP + 1))" | while read -r old; do
    rm -f -- "$old"; log INFO "removido antigo: $old"
  done
fi
EOF

  cat > "$APP_DIR/scripts/update.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
log() { echo "$(date '+%Y-%m-%dT%H:%M:%S%z') [$1] [update] ${*:2}"; }

log INFO "backup antes da atualização"
"$ROOT/scripts/backup.sh"

log INFO "reconstruindo imagem"
docker compose build --pull
docker compose up -d
log INFO "concluído"
EOF

  chmod 755 "$APP_DIR"/docker/bin/* "$APP_DIR"/scripts/*.sh
  chmod 644 "$APP_DIR"/docker/lib/common.sh "$APP_DIR"/docker/supervisord.conf \
            "$APP_DIR"/Dockerfile "$APP_DIR"/docker-compose.yml "$APP_DIR"/.dockerignore
}

# Instala o atalho "mt-menu" (cópia deste script em $APP_DIR/scripts)
instalar_atalho() {
  local alvo="$APP_DIR/scripts/mt-menu.sh"
  if [[ "$SELF" != "$alvo" ]]; then
    cp -f "$SELF" "$alvo" 2>/dev/null && chmod 755 "$alvo" || return 0
  fi
  printf '#!/usr/bin/env bash\nexec bash %q "$@"\n' "$alvo" > "$MENU_BIN" 2>/dev/null \
    && chmod 755 "$MENU_BIN" 2>/dev/null || true
}

# -----------------------------------------------------------------------------
# Etapa 1 — Instalação base
# -----------------------------------------------------------------------------
etapa_instalar_base() {
  title "1 · Instalação base"
  require_root

  case "$(. /etc/os-release 2>/dev/null; echo "${ID:-?}")" in
    ubuntu|debian) ;;
    *) warn "Sistema não é Ubuntu/Debian; o script foi pensado para eles." ;;
  esac

  if ! command -v curl >/dev/null 2>&1; then
    info "Instalando curl..."
    apt-get update -qq && apt-get install -y -qq curl ca-certificates || { err "não consegui instalar curl"; return 1; }
  fi

  if ! command -v docker >/dev/null 2>&1; then
    run_spin "Instalando Docker (get.docker.com)" /tmp/mt-docker-install.log \
      bash -c 'curl -fsSL https://get.docker.com | DEBIAN_FRONTEND=noninteractive sh' || return 1
  fi
  command -v systemctl >/dev/null 2>&1 && systemctl enable --now docker >/dev/null 2>&1
  docker compose version >/dev/null 2>&1 || { err "Docker Compose v2 não encontrado"; return 1; }
  docker info >/dev/null 2>&1 || { err "Docker daemon não está rodando: systemctl start docker"; return 1; }
  ok "Docker OK (habilitado no boot)"

  mkdir -p "$APP_DIR"
  local free_gb
  free_gb="$(df -BG "$APP_DIR" 2>/dev/null | awk 'NR==2{gsub(/G/,"",$4); print $4+0}')"
  if [[ -z "$free_gb" || "$free_gb" == "0" ]]; then
    warn "não foi possível medir o espaço livre; seguindo"
  elif (( free_gb < 10 )); then
    err "espaço insuficiente em $APP_DIR: ${free_gb}GB livres (mínimo 10GB)"; return 1
  else
    ok "Espaço em disco: ${free_gb}GB livres"
  fi

  info "Gerando arquivos em $APP_DIR"
  gerar_arquivos || { err "falha ao gerar arquivos"; return 1; }

  info "Configurando host (swap, limites, .env, cron)..."
  bash "$APP_DIR/scripts/setup-host.sh" 2>&1 | sed 's/^/    /'
  if [[ "${PIPESTATUS[0]}" -ne 0 ]]; then err "setup-host falhou"; return 1; fi
  echo
  escolher_tz
  echo
  escolher_wine
  instalar_atalho

  echo
  cd "$APP_DIR" || return 1
  run_spin "Construindo imagem Docker (5–15 min na 1ª vez)" "$APP_DIR/data/logs/host-build.log" \
    timeout 1800 docker compose -f "$COMPOSE_FILE" build --progress plain || return 1
  dc up -d >/dev/null 2>&1 || { err "docker compose up falhou"; return 1; }

  if wait_healthy; then
    printf '\r\033[K'; ok "Container saudável"
  else
    printf '\r\033[K'; warn "Healthcheck não ficou saudável no prazo. Veja: mt-menu → 4 (Status)"
  fi

  echo
  ok "${C_BOLD}Instalação base concluída${C_RESET}"
  echo
  mostrar_acesso
  echo
  echo "  ${C_BOLD}Próximo passo:${C_RESET} opção 2 (instalar MT4/MT5), depois opção 3 (robôs)."
  echo "  ${C_DIM}Atalho para voltar a este menu: sudo mt-menu${C_RESET}"
}

# -----------------------------------------------------------------------------
# Etapa 2 — Instalar MT4 + MT5
# -----------------------------------------------------------------------------
instalar_terminal() { # instalar_terminal mt4|mt5
  local id="$1" args=() rc=0 log="$APP_DIR/data/logs/host-install-$1.log"

  # MT4 com prefixo win32 não executa instalador de 64 bits ("Bad EXE format").
  # Se o MT4 ainda não foi instalado, migra para win64 e recria o prefixo.
  if [[ "$id" == "mt4" && ! -s "$APP_DIR/data/prefix-mt4/.mt_exe_path" ]]; then
    local migrou=0
    if [[ "$(env_get MT4_ARCH)" != "win64" ]]; then env_set MT4_ARCH win64; migrou=1; fi
    if grep -qs '^#arch=win32' "$APP_DIR/data/prefix-mt4/system.reg"; then
      warn "Prefixo antigo do MT4 é win32; recriando como win64..."
      dc exec -T mt mt-sv stop mt4 >/dev/null 2>&1 || true
      find "$APP_DIR/data/prefix-mt4" -mindepth 1 -delete 2>/dev/null
      migrou=1
    fi
    if (( migrou )); then
      dc up -d --force-recreate >/dev/null 2>&1
      wait_supervisor || { err "container não voltou"; return 1; }
    fi
  fi

  if [[ -s "$APP_DIR/data/prefix-$id/.mt_exe_path" ]]; then
    warn "${id^^} já está instalado."
    if confirm "Reinstalar (--force)?"; then args+=(--force); else return 0; fi
  fi

  echo
  info "Instalando ${id^^} — leva de 10 a 30 min. Pode acompanhar pelo noVNC (opção 7 mostra como)."
  dc exec -T mt mt-sv stop "$id" >/dev/null 2>&1 || true
  sleep 2

  run_spin "Instalando ${id^^}" "$log" dc exec -T mt mt-install "$id" "${args[@]}" || rc=$?

  # Reinicia o programa no supervisor (ele foi parado manualmente acima)
  dc exec -T mt mt-sv start "$id" >/dev/null 2>&1 || true
  if (( rc == 0 )); then
    ok "${id^^} instalado e iniciando"
  else
    err "${id^^} falhou. Log detalhado: $APP_DIR/data/logs/setup-$id.log"
  fi
  return "$rc"
}

# Remove um terminal: para o programa, mata o wineserver do prefixo e apaga o prefixo
# inteiro (terminal, conta, EAs, dependências do Wine). Na reinstalação tudo é refeito.
remover_terminal() { # remover_terminal mt4|mt5
  local id="$1" dir="$APP_DIR/data/prefix-$1"
  if container_running; then
    dc exec -T mt mt-sv stop "$id" >/dev/null 2>&1 || true
    dc exec -T -e WINEPREFIX="/home/mt/prefix/$id" mt wineserver -k >/dev/null 2>&1 || true
    sleep 2
  fi
  find "$dir" -mindepth 1 -delete 2>/dev/null
  if [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
    ok "${id^^} removido"
  else
    err "não consegui apagar tudo em $dir"
    return 1
  fi
}

desinstalar_terminais() {
  local esc ids=() id existentes=()
  echo
  echo "  ${C_BOLD}Qual terminal desinstalar?${C_RESET}"
  echo "    1) MT4"
  echo "    2) MT5"
  echo "    3) Ambos"
  echo "    0) Voltar"
  read -rp "  Opção [0-3]: " esc || true
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
      info "${id^^} já está vazio/não instalado"
    fi
  done
  ((${#existentes[@]} > 0)) || return 0

  echo
  warn "Vai APAGAR ${existentes[*]^^}: o terminal, a conta logada, os EAs/indicadores e as"
  warn "configurações. Os arquivos em $ROBOS_DIR e os backups NÃO são afetados."
  confirm "Confirmar a desinstalação de ${existentes[*]^^}?" || { info "cancelado"; return 0; }

  for id in "${existentes[@]}"; do remover_terminal "$id"; done
  echo
  info "Para instalar de novo, use esta mesma opção e escolha Instalar."
}

etapa_instalar_terminais() {
  title "2 · MT4 / MT5 — instalar ou desinstalar"
  require_root
  need_base || return 1

  # o container roda como uid 1000; dono errado em data/ causa loop de reinício
  chown -R 1000:1000 "$APP_DIR/data" 2>/dev/null
  chmod 700 "$APP_DIR/data/prefix-mt4" "$APP_DIR/data/prefix-mt5" 2>/dev/null

  local acao
  echo "  ${C_BOLD}O que deseja fazer?${C_RESET}"
  echo "    1) Instalar MT4 / MT5"
  echo "    2) Desinstalar MT4 / MT5"
  echo "    0) Voltar"
  read -rp "  Opção [0-2] (Enter=1): " acao || true
  case "${acao:-1}" in
    1) ;;
    2) desinstalar_terminais; return $? ;;
    *) return 0 ;;
  esac
  echo

  if ! container_running; then
    info "Container parado — iniciando..."
    dc up -d >/dev/null 2>&1
  fi
  info "Aguardando serviços internos..."
  wait_supervisor || { err "supervisord não respondeu; veja os logs (menu 6)"; return 1; }

  echo
  echo "  ${C_BOLD}Qual terminal instalar?${C_RESET} ${C_DIM}(instalador oficial da MetaQuotes)${C_RESET}"
  echo "    1) MT4"
  echo "    2) MT5"
  echo "    3) Ambos (MT4 primeiro, depois MT5)"
  echo "    0) Voltar"
  local escolha
  read -rp "  Opção [0-3]: " escolha || true
  case "${escolha:-}" in
    1) instalar_terminal mt4 ;;
    2) instalar_terminal mt5 ;;
    3)
      instalar_terminal mt4
      echo
      info "Aguardando 30s para a RAM estabilizar antes do MT5..."
      sleep 30
      instalar_terminal mt5
      ;;
    0) return 0 ;;
    *) warn "opção inválida" ;;
  esac
}

# -----------------------------------------------------------------------------
# Etapa 3 — Robôs / Indicadores
# -----------------------------------------------------------------------------
# Pasta MQL do terminal NO HOST. Como o terminal roda com /portable, os dados
# ficam ao lado do terminal.exe — usamos o caminho do marcador, não "o primeiro
# MQL4 que o find achar" (que pode ser a pasta AppData, ignorada no modo portable).
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

# Estrutura onde você coloca os arquivos; a opção 3 do menu lê daqui.
criar_estrutura_robos() {
  mkdir -p "$ROBOS_DIR"/{MT4,MT5}/{Experts,Indicators} "$ROBOS_DIR/sets" "$BACKUP_DIR" 2>/dev/null || true
  if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
    chown -R "$SUDO_USER:" "$ROBOS_DIR" 2>/dev/null || true
    chown "$SUDO_USER:" "$BACKUP_DIR" 2>/dev/null || true
  fi
}

etapa_instalar_robos() {
  title "3 · Robôs, Indicadores e Sets"
  require_root
  need_base || return 1
  criar_estrutura_robos

  echo "  Coloque os arquivos na pasta certa e depois rode esta opção:"
  echo
  echo "    ${C_CYAN}$ROBOS_DIR/MT4/Experts${C_RESET}       ${C_DIM}robôs do MT4 (.ex4)${C_RESET}"
  echo "    ${C_CYAN}$ROBOS_DIR/MT4/Indicators${C_RESET}    ${C_DIM}indicadores do MT4 (.ex4)${C_RESET}"
  echo "    ${C_CYAN}$ROBOS_DIR/MT5/Experts${C_RESET}       ${C_DIM}robôs do MT5 (.ex5)${C_RESET}"
  echo "    ${C_CYAN}$ROBOS_DIR/MT5/Indicators${C_RESET}    ${C_DIM}indicadores do MT5 (.ex5)${C_RESET}"
  echo "    ${C_CYAN}$ROBOS_DIR/sets${C_RESET}              ${C_DIM}arquivos .set (MT4 e MT5 na mesma pasta)${C_RESET}"
  echo
  echo "  ${C_DIM}Do seu PC: scp -P $SSH_PORT MeuRobo.ex5 root@$(server_ip):$ROBOS_DIR/MT5/Experts/${C_RESET}"
  echo

  local f resto
  # avisos: arquivo no lugar errado
  while IFS= read -r -d '' f; do
    warn "ignorado (extensão do MT5 na pasta do MT4): ${f#"$ROBOS_DIR"/}"
  done < <(find "$ROBOS_DIR/MT4" -maxdepth 2 -type f \( -iname '*.ex5' -o -iname '*.mq5' \) -print0 2>/dev/null)
  while IFS= read -r -d '' f; do
    warn "ignorado (extensão do MT4 na pasta do MT5): ${f#"$ROBOS_DIR"/}"
  done < <(find "$ROBOS_DIR/MT5" -maxdepth 2 -type f \( -iname '*.ex4' -o -iname '*.mq4' \) -print0 2>/dev/null)
  while IFS= read -r -d '' f; do
    warn "solto na raiz (mova para MT4/ ou MT5/): $(basename "$f")"
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
        err "${id^^}/$kind: ${#files[@]} arquivo(s) aguardando, mas o ${id^^} não está instalado (opção 2)."
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
          err "falha ao copiar $base"
        fi
      done
    done
  done

  # ---- Sets (.set): uma pasta só; pergunta o terminal na primeira vez ----
  # A escolha fica gravada em sets/.destinos; nas próximas vezes copia sem perguntar.
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
      echo "  ${C_BOLD}$base${C_RESET} ${C_DIM}(set novo)${C_RESET}"
      echo "    1) MT4    2) MT5    0) Deixar como está"
      read -rp "    Para qual terminal? [0-2]: " resp || true
      case "${resp:-0}" in
        1) alvo="mt4" ;;
        2) alvo="mt5" ;;
        *) info "  deixado em sets/: $base"; deixados=$((deixados + 1)); continue ;;
      esac
      novo_set=1
    else
      novo_set=0
    fi
    destino="$(mql_dest "$alvo" Presets || true)"
    if [[ -z "$destino" ]]; then
      err "$base: ${alvo^^} ainda não está instalado (opção 2)."
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
      err "falha ao copiar $base"
      continue
    fi
    (( novo_set )) && printf '%s|%s\n' "$base" "$alvo" >> "$memo"
  done

  echo
  if (( total == 0 )); then
    warn "Nenhum arquivo encontrado nas pastas acima."
    return 0
  fi
  info "$total arquivo(s) nas pastas: $novos novo(s)/atualizado(s), $iguais já estavam iguais, $pendentes pendente(s), $deixados deixado(s) em sets/."
  if (( novos > 0 )); then
    if container_running && confirm "Reiniciar MT4/MT5 para o Navigator reconhecer os novos arquivos?"; then
      dc exec -T mt mt-sv restart mt4 >/dev/null 2>&1 || true
      dc exec -T mt mt-sv restart mt5 >/dev/null 2>&1 || true
      ok "Terminais reiniciados (os que estão instalados)"
    fi
    echo
    echo "  ${C_DIM}No MetaTrader: Navigator → Expert Advisors / Indicators (ou botão direito → Atualizar).${C_RESET}"
    echo "  ${C_DIM}Lembre de ativar \"Algo Trading\" / \"Permitir negociação automatizada\" no terminal.${C_RESET}"
  fi
}

# -----------------------------------------------------------------------------
# Etapa 4 — Status / Diagnóstico
# -----------------------------------------------------------------------------
etapa_status() {
  title "4 · Status e diagnóstico"
  require_root
  need_base || return 1
  local cn; cn="$(container_name)"

  echo "  ${C_BOLD}Container${C_RESET}"; rule 30
  dc ps 2>&1 | sed 's/^/  /' || true
  echo

  if container_running; then
    echo "  ${C_BOLD}Serviços internos (supervisord)${C_RESET}"; rule 30
    dc exec -T mt mt-sv status 2>/dev/null | sed 's/^/  /' || warn "não foi possível consultar o supervisord"
    echo
    echo "  ${C_BOLD}Processos dos terminais${C_RESET}"; rule 30
    dc exec -T mt ps aux 2>/dev/null | grep -E 'terminal(64)?\.exe' | grep -v grep | cut -c1-$((COLS - 2)) | sed 's/^/  /' \
      || echo "  (nenhum terminal rodando)"
    echo
    echo "  ${C_BOLD}Recursos${C_RESET}"; rule 30
    docker stats --no-stream --format '  CPU {{.CPUPerc}}   RAM {{.MemUsage}} ({{.MemPerc}})   PIDs {{.PIDs}}' "$cn" 2>/dev/null || true
    free -m | awk 'NR==1||/Mem|Swap/' | sed 's/^/  /'
    df -h "$APP_DIR" | awk 'NR==2{print "  Disco: " $3 " usados de " $2 " (" $5 ")"}'
    echo
    echo "  ${C_BOLD}Últimas linhas do log${C_RESET}"; rule 30
    dc exec -T mt tail -8 /home/mt/logs/mt-docker.log 2>/dev/null | cut -c1-$((COLS - 2)) | sed 's/^/  /' || true
  else
    warn "Container não está rodando (menu 5 → Iniciar)."
  fi
  echo
  mostrar_acesso
}

# -----------------------------------------------------------------------------
# Etapa 5 — Operação
# -----------------------------------------------------------------------------
etapa_operacao() {
  need_base || { pause; return; }
  local op
  while true; do
    title "5 · Operação"
    painel; echo
    echo "    1) Reiniciar o container inteiro"
    echo "    2) Parar o container"
    echo "    3) Iniciar o container"
    echo "    4) Reiniciar MT4        5) Reiniciar MT5"
    echo "    6) Parar MT4            7) Parar MT5"
    echo "    8) Iniciar MT4          9) Iniciar MT5"
    echo "    0) Voltar"
    echo
    read -rp "  Opção [0-9]: " op || { echo; continue; }
    case "$op" in
      1) confirm "Reiniciar o container inteiro?" && { dc restart >/dev/null 2>&1 && ok "container reiniciado" || err "falhou"; } ;;
      2) confirm "Parar o container (os terminais fecham)?" && { dc stop >/dev/null 2>&1 && ok "container parado" || err "falhou"; } ;;
      3) dc start >/dev/null 2>&1 && ok "container iniciado" || err "falhou" ;;
      4) dc exec -T mt mt-sv restart mt4 2>&1 | sed 's/^/  /' ;;
      5) dc exec -T mt mt-sv restart mt5 2>&1 | sed 's/^/  /' ;;
      6) dc exec -T mt mt-sv stop mt4 2>&1 | sed 's/^/  /' ;;
      7) dc exec -T mt mt-sv stop mt5 2>&1 | sed 's/^/  /' ;;
      8) dc exec -T mt mt-sv start mt4 2>&1 | sed 's/^/  /' ;;
      9) dc exec -T mt mt-sv start mt5 2>&1 | sed 's/^/  /' ;;
      0) return ;;
      *) warn "opção inválida" ;;
    esac
    pause
  done
}

# -----------------------------------------------------------------------------
# Etapa 6 — Manutenção
# -----------------------------------------------------------------------------
fazer_backup() {
  run_spin "Gerando backup" "$APP_DIR/data/logs/host-backup.log" bash "$APP_DIR/scripts/backup.sh" || return 1
  ls -1t "$BACKUP_DIR"/mt-backup-*.tar.gz 2>/dev/null | head -3 | while read -r b; do
    echo "    ${C_DIM}$(du -h "$b" | cut -f1)  $b${C_RESET}"
  done
  echo "  ${C_DIM}Pasta: $BACKUP_DIR ($(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1) no total; nada é apagado automaticamente)${C_RESET}"
}

restaurar_backup() {
  local bks=() b i=1 n
  while IFS= read -r b; do bks+=("$b"); done < <(ls -1t "$BACKUP_DIR"/mt-backup-*.tar.gz 2>/dev/null)
  if ((${#bks[@]} == 0)); then warn "Nenhum backup em $BACKUP_DIR"; return 0; fi
  echo "  ${C_BOLD}Backups disponíveis:${C_RESET}"
  for b in "${bks[@]}"; do
    printf '    %2d) %s  %s(%s)%s\n' "$i" "$(basename "$b")" "$C_DIM" "$(du -h "$b" | cut -f1)" "$C_RESET"
    i=$((i + 1))
  done
  read -rp "  Restaurar qual? [1-${#bks[@]}, 0=cancelar]: " n || true
  if ! [[ "${n:-0}" =~ ^[0-9]+$ ]] || (( n < 1 || n > ${#bks[@]} )); then info "cancelado"; return 0; fi
  b="${bks[n-1]}"
  warn "Isso SUBSTITUI os dados atuais de MT4/MT5 (contas, EAs, configurações) pelo conteúdo do backup."
  confirm "Confirmar restauração de $(basename "$b")?" || { info "cancelado"; return 0; }

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
    ok "Backup restaurado"
  else
    err "falha ao extrair o backup"
  fi
  dc start >/dev/null 2>&1 && ok "container iniciado"
}

trocar_senha_vnc() {
  local pw
  read -rsp "  Nova senha VNC (mín. 8; só os 8 primeiros caracteres valem): " pw || true; echo
  if (( ${#pw} < 8 )); then err "senha curta demais"; return 1; fi
  pw="${pw:0:8}"
  env_set VNC_PASSWORD "$pw"
  info "Recriando o container para aplicar..."
  dc up -d --force-recreate >/dev/null 2>&1 && ok "Senha alterada" || err "falhou ao recriar"
}

desinstalar() {
  warn "Isto remove o container e a imagem. Seus dados só serão apagados se você pedir."
  confirm "Continuar com a desinstalação?" || { info "cancelado"; return 0; }
  dc down --rmi local >/dev/null 2>&1 && ok "container e imagem removidos"
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
  echo "  Dados das contas continuam em: ${C_CYAN}$APP_DIR${C_RESET}"
  echo "  Robôs e backups ficam em ${C_CYAN}$ROBOS_DIR${C_RESET} e ${C_CYAN}$BACKUP_DIR${C_RESET} (não são apagados)."
  local t; read -rp "  Para APAGAR TUDO digite APAGAR (Enter mantém): " t || true
  if [[ "${t:-}" == "APAGAR" ]]; then
    rm -rf "${APP_DIR:?}" && ok "$APP_DIR apagado"
  else
    info "dados mantidos"
  fi
}

etapa_manutencao() {
  need_base || { pause; return; }
  local op
  while true; do
    title "6 · Manutenção"
    echo "    1) Fazer backup agora"
    echo "    2) Restaurar um backup"
    echo "    3) Atualizar (backup + reconstruir imagem)"
    echo "    4) Ver logs em tempo real (Ctrl+C volta)"
    echo "    5) Consumo de recursos ao vivo (Ctrl+C volta)"
    echo "    6) Trocar senha do VNC"
    echo "    7) Trocar fuso horário"
    echo "    8) Desinstalar"
    echo "    0) Voltar"
    echo
    read -rp "  Opção [0-8]: " op || { echo; continue; }
    case "$op" in
      1) fazer_backup ;;
      2) restaurar_backup ;;
      3) if confirm "Fazer backup, reconstruir imagem e reiniciar?"; then
           run_spin "Atualizando" "$APP_DIR/data/logs/host-update.log" bash "$APP_DIR/scripts/update.sh"
         fi ;;
      4) dc logs -f --tail 50 mt ;;
      5) docker stats "$(container_name)" ;;
      6) trocar_senha_vnc ;;
      7) escolher_tz && confirm "Reiniciar o container para aplicar o novo fuso?" && dc up -d --force-recreate >/dev/null 2>&1 && ok "aplicado" ;;
      8) desinstalar; [[ -d "$APP_DIR" ]] || return ;;
      0) return ;;
      *) warn "opção inválida" ;;
    esac
    pause
  done
}

etapa_acesso() {
  title "7 · Como acessar"
  need_base || return 1
  mostrar_acesso
}

# -----------------------------------------------------------------------------
# Instalação guiada (tudo em sequência)
# -----------------------------------------------------------------------------
etapa_guiada() {
  title "A · Instalação guiada"
  echo "  Vou executar, em ordem: ${C_BOLD}base → MT4/MT5 → robôs${C_RESET}."
  echo "  Tempo total estimado: 30–60 min (a maior parte é automática)."
  echo
  confirm "Começar?" || return 0
  etapa_instalar_base || { err "Base falhou; interrompendo."; return 1; }
  echo; read -rp "  ENTER para seguir ao MT4/MT5..." _ || true
  etapa_instalar_terminais
  echo; read -rp "  ENTER para seguir aos robôs/indicadores..." _ || true
  etapa_instalar_robos
  echo
  ok "${C_BOLD}Tudo pronto.${C_RESET} Use ${C_CYAN}sudo mt-menu${C_RESET} quando quiser voltar."
}

# -----------------------------------------------------------------------------
# Menu principal
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
    echo "  ${C_BOLD}${C_CYAN}MetaTrader 4 + 5 em Docker · noVNC${C_RESET}"
    rule
    painel
    rule
    echo "  ${C_DIM}Robôs: $ROBOS_DIR${C_RESET}"
    echo "  ${C_DIM}Backups: $BACKUP_DIR${C_RESET}"
    echo
    echo "   ${C_BOLD}A)${C_RESET} Instalação guiada ${C_DIM}(recomendado na 1ª vez)${C_RESET}"
    echo
    echo "   ${C_BOLD}1)${C_RESET} Instalar base              ${C_DIM}Docker, swap, imagem${C_RESET}"
    echo "   ${C_BOLD}2)${C_RESET} Instalar / remover MT4/5   ${C_DIM}instala ou desinstala${C_RESET}"
    echo "   ${C_BOLD}3)${C_RESET} Robôs, Indicadores e Sets  ${C_DIM}.ex4 .ex5 .set${C_RESET}"
    echo "   ${C_BOLD}4)${C_RESET} Status e diagnóstico"
    echo "   ${C_BOLD}5)${C_RESET} Operação                   ${C_DIM}iniciar / parar / reiniciar${C_RESET}"
    echo "   ${C_BOLD}6)${C_RESET} Manutenção                 ${C_DIM}backup, update, logs, senha${C_RESET}"
    echo "   ${C_BOLD}7)${C_RESET} Como acessar               ${C_DIM}senha VNC e túnel SSH${C_RESET}"
    echo "   ${C_BOLD}0)${C_RESET} Sair"
    echo
    read -rp "  Escolha [A,0-7]: " opt || { echo; continue; }
    case "${opt,,}" in
      a) run_etapa etapa_guiada ;;
      1) run_etapa etapa_instalar_base ;;
      2) run_etapa etapa_instalar_terminais ;;
      3) run_etapa etapa_instalar_robos ;;
      4) run_etapa etapa_status ;;
      5) etapa_operacao ;;
      6) etapa_manutencao ;;
      7) run_etapa etapa_acesso ;;
      0|q|sair) echo; info "Até logo."; exit 0 ;;
      "") ;;
      *) warn "opção inválida"; sleep 1 ;;
    esac
  done
}

main() {
  require_root
  # mantém o atalho "mt-menu" sempre na versão mais recente deste script
  [[ -d "$APP_DIR/scripts" ]] && instalar_atalho
  criar_estrutura_robos
  case "${1:-menu}" in
    menu)      menu ;;
    guiada)    etapa_guiada ;;
    base)      etapa_instalar_base ;;
    terminais) etapa_instalar_terminais ;;
    robos)     etapa_instalar_robos ;;
    status)    etapa_status ;;
    backup)    need_base && fazer_backup ;;
    -h|--help|ajuda)
      sed -n '2,30p' "$SELF" | sed 's/^# \{0,1\}//' ;;
    *) die "comando desconhecido: $1 (use: menu guiada base terminais robos status backup)" ;;
  esac
}

# Permite "source" para testes sem executar o menu
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
