#!/usr/bin/env bash
# =============================================================================
# install-mt-docker.sh — MT4/MT5 installer + manager in Docker with noVNC
#                        Instalador + gerenciador MT4/MT5 em Docker com noVNC
# =============================================================================
# EN: Interactive menu for Ubuntu/Debian VPS WITHOUT a GUI (1-2 GB RAM).
#     Uses the OFFICIAL MetaQuotes installers (no broker setup needed).
# PT: Menu interativo para VPS Ubuntu/Debian SEM interface gráfica (1-2 GB de RAM).
#     Usa os instaladores OFICIAIS da MetaQuotes (não precisa configurar corretora).
#
# Usage / Uso:
#   sudo bash install-mt-docker.sh [--lang en|pt] [command]
#     (no command)  menu / abre o menu
#     guided        full guided install / instalação guiada   (pt: guiada)
#     base          base install / instalação base
#     terminals     install/remove MT4/MT5                    (pt: terminais)
#     bots          copy EAs/indicators/sets                  (pt: robos)
#     status        status / diagnóstico
#     backup        backup now / backup agora
#     language      change language / trocar idioma           (pt: idioma)
#
# After the first run the shortcut  sudo mt-menu  is available.
# Depois da primeira execução, o atalho  sudo mt-menu  fica disponível.
#
# Settings (optional) / Configuração (opcional):
#   APP_DIR=/opt/mt-docker   base directory / diretório base
#   SSH_PORT=22              VPS SSH port (only used in messages) / porta SSH (só para as mensagens)
#   ROBOS_DIR, BACKUP_DIR    where bots and backups live / onde ficam robôs e backups
#   These can be set on the command line or in a .env (in $APP_DIR or next to the
#   script). Command line wins over .env. / Podem ser passadas na linha de comando
#   ou num .env (em $APP_DIR ou ao lado do script). A linha de comando vence o .env.
#   The Wine version is chosen during base install and saved in $APP_DIR/.env
#   (WINE_VERSION). / A versão do Wine é escolhida na instalação base e fica
#   salva em $APP_DIR/.env (WINE_VERSION).
#
# Bots/indicators folder ("EAs") is created INSIDE the cloned project folder on first run:
# A pasta "EAs" (Expert Advisors/robôs) é criada DENTRO da pasta do projeto clonado na primeira execução:
#   MT4/Experts  MT4/Indicators  (.ex4 / .mq4)
#   MT5/Experts  MT5/Indicators  (.ex5 / .mq5)
#   sets/                        (.set for MT4 and MT5 / .set de MT4 e MT5)
#
# NOTE — Line endings (CRLF): this file must use Unix (LF) line endings.
# NOTA — Fins de linha (CRLF): este arquivo precisa estar com fim de linha Unix (LF).
#   If it came from Windows / se veio do Windows:  sed -i 's/\r$//' install-mt-docker.sh
# =============================================================================
set -uo pipefail
# (no "set -e" in the menu: an error in one step returns to the menu instead of
#  closing everything. Scripts generated for the container do use set -e.)
# (sem "set -e" no menu: um erro numa etapa volta ao menu em vez de fechar tudo.
#  Os scripts gerados para dentro do container usam set -e normalmente.)

# -----------------------------------------------------------------------------
# Global configuration / Configuração global
# -----------------------------------------------------------------------------
APP_DIR="${APP_DIR:-/opt/mt-docker}"
LANG_UI=""   # en | pt  (chosen on first run, saved in $APP_DIR/.lang)

# T "english" "português"  → prints the string for the current UI language.
T() { if [[ "${LANG_UI:-en}" == "pt" ]]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }

# Loads a FEW host-side settings from a .env, WITHOUT exporting them and only if
# not already set (command line > .env > defaults). We deliberately do NOT source
# the whole file: exporting TZ/VNC_PASSWORD into our environment would make
# "docker compose" prefer those stale values over the .env after we edit it.
_load_env_file() {
  local f line k v
  # Scan all candidates; command-line / already-set vars win. Do NOT return after the
  # first file — $APP_DIR/.env may exist without SSH_PORT/ROBOS_DIR/BACKUP_DIR, and we
  # still want the .env next to the script.
  for f in "${ENV_FILE_OVERRIDE:-}" "$APP_DIR/.env" \
           "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "$0")")/.env"; do
    [[ -n "$f" && -r "$f" ]] || continue
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%$'\r'}"
      [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]] || continue
      k="${BASH_REMATCH[1]}"; v="${BASH_REMATCH[2]}"
      case "$k" in SSH_PORT|ROBOS_DIR|BACKUP_DIR) ;; *) continue ;; esac
      v="${v#\"}"; v="${v%\"}"; v="${v#\'}"; v="${v%\'}"
      v="${v%$'\r'}"
      if [[ -z "${!k+x}" ]]; then printf -v "$k" '%s' "$v"; fi
    done < "$f"
  done
  return 0
}
_load_env_file

COMPOSE_FILE="$APP_DIR/docker-compose.yml"
ENV_FILE="$APP_DIR/.env"
MENU_BIN="/usr/local/bin/mt-menu"

SELF="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "$SELF")" && pwd)"

# "EAs" and "backups" folders live inside the cloned project folder (git root of the script)
# and are remembered in $APP_DIR/.robos_dir so the "mt-menu" shortcut uses the same one.
# To move them: set ROBOS_DIR=/path and/or BACKUP_DIR=/path when running the script.
# Pastas "EAs" e "backups": ficam dentro da pasta do projeto clonado (raiz do git) e são
# lembradas em $APP_DIR/.robos_dir (usadas também pelo atalho "mt-menu").
resolver_robos_dir() {
  local salvo="" base old_robos="" sb="" novo_b
  # BASE = the cloned project folder (git root of the script, or the script's own folder).
  # When run through the "mt-menu" copy (inside $APP_DIR) the base is $APP_DIR.
  # BASE = pasta do projeto clonado (raiz do git do script, ou a pasta do próprio script).
  # Pelo atalho "mt-menu" (cópia dentro de $APP_DIR) a base é $APP_DIR.
  if [[ "$SCRIPT_DIR" == "$APP_DIR" || "$SCRIPT_DIR" == "$APP_DIR"/* ]]; then
    base="$APP_DIR"
  else
    base="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
    [[ -n "$base" ]] || base="$SCRIPT_DIR"
  fi

  if [[ -z "${ROBOS_DIR:-}" ]]; then
    [[ -f "$APP_DIR/.robos_dir" ]] && salvo="$(<"$APP_DIR/.robos_dir")"
    # Old versions saved ".../robos" (often in the wrong place, e.g. /home/robos).
    # Move it to "<base>/EAs" once and use that from now on.
    # Versões antigas salvavam ".../robos" (às vezes no lugar errado, ex.: /home/robos).
    # Move uma vez para "<base>/EAs" e passa a usar essa.
    if [[ -n "$salvo" && "${salvo##*/}" == "robos" ]]; then
      old_robos="$salvo"
      if [[ ! -e "$base/EAs" ]] && { [[ ! -d "$salvo" ]] || mv "$salvo" "$base/EAs" 2>/dev/null; }; then
        salvo="$base/EAs"
      fi
    fi
    ROBOS_DIR="${salvo:-$base/EAs}"
  fi
  ROBOS_DIR="$(realpath -m "$ROBOS_DIR" 2>/dev/null || echo "$ROBOS_DIR")"

  if [[ -z "${BACKUP_DIR:-}" ]]; then
    [[ -f "$APP_DIR/.backup_dir" ]] && sb="$(<"$APP_DIR/.backup_dir")"
    # carry the old backups folder along with the migrated bots folder
    if [[ -n "$old_robos" && "$sb" == "$(dirname "$old_robos")/backups" && ! -e "$base/backups" ]]; then
      mv "$sb" "$base/backups" 2>/dev/null && sb="$base/backups"
    fi
    novo_b="$(dirname "$ROBOS_DIR")/backups"
    BACKUP_DIR="${sb:-$novo_b}"
  fi
  BACKUP_DIR="$(realpath -m "$BACKUP_DIR" 2>/dev/null || echo "$BACKUP_DIR")"
  if mkdir -p "$APP_DIR" 2>/dev/null; then
    printf '%s\n' "$ROBOS_DIR" > "$APP_DIR/.robos_dir" 2>/dev/null || true
    printf '%s\n' "$BACKUP_DIR" > "$APP_DIR/.backup_dir" 2>/dev/null || true
  fi
}
resolver_robos_dir

# -----------------------------------------------------------------------------
# Language / Idioma
# -----------------------------------------------------------------------------
norm_lang() { # norm_lang VALUE → sets LANG_UI (en|pt); returns 1 if invalid
  local l="${1,,}"
  case "$l" in
    en|en_*|en-*|english|ingles|inglês) LANG_UI="en" ;;
    pt|pt_*|pt-*|ptbr|portugues|português|br) LANG_UI="pt" ;;
    *) return 1 ;;
  esac
}

init_lang() { # loads the saved language, if any
  local l=""
  [[ -r "$APP_DIR/.lang" ]] && l="$(<"$APP_DIR/.lang")"
  [[ -n "$l" ]] && norm_lang "$l" || true
}

salvar_idioma() {
  mkdir -p "$APP_DIR" 2>/dev/null || true
  printf '%s\n' "$LANG_UI" > "$APP_DIR/.lang" 2>/dev/null || true
  # the container reads MT_LANG for its own log messages (applied on next recreate)
  if [[ -f "$ENV_FILE" ]]; then env_set MT_LANG "$LANG_UI"; fi
}

escolher_idioma() {
  local guess=1 opt
  [[ "${LC_ALL:-${LANG:-}}" == pt* ]] && guess=2
  if [[ -t 0 && -t 1 ]]; then
    echo
    echo "  ${C_BOLD}${C_CYAN}Language / Idioma${C_RESET}"
    rule
    echo
    echo "    1) English"
    echo "    2) Português (Brasil)"
    echo
    read -rp "  [1-2] (Enter=$guess): " opt || true
    case "${opt:-$guess}" in
      2) LANG_UI="pt" ;;
      *) LANG_UI="en" ;;
    esac
  else
    if (( guess == 2 )); then LANG_UI="pt"; else LANG_UI="en"; fi
  fi
  salvar_idioma
  ok "$(T "Language: English" "Idioma: Português (Brasil)")"
}

usage() {
  if [[ "${LANG_UI:-en}" == "pt" ]]; then
    cat <<'EOF'
Uso: sudo bash install-mt-docker.sh [--lang en|pt] [comando]

Comandos:
  (nenhum)    abre o menu
  guiada      instalação guiada completa
  base        instalação base (Docker, swap, imagem)
  terminais   instalar/remover MT4/MT5
  robos       copiar robôs, indicadores e sets
  status      status e diagnóstico
  backup      backup agora
  idioma      trocar o idioma

Depois da primeira execução, o atalho  sudo mt-menu  fica disponível.
EOF
  else
    cat <<'EOF'
Usage: sudo bash install-mt-docker.sh [--lang en|pt] [command]

Commands:
  (none)      open the menu
  guided      full guided install
  base        base install (Docker, swap, image)
  terminals   install/remove MT4/MT5
  bots        copy EAs, indicators and sets
  status      status and diagnostics
  backup      backup now
  language    change the language

After the first run, the shortcut  sudo mt-menu  becomes available.
EOF
  fi
}

# -----------------------------------------------------------------------------
# Visuals (plain terminal; falls back to ASCII if the locale isn't UTF-8)
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
  [[ $EUID -eq 0 ]] || die "$(T "run as root: sudo bash $SELF" "execute como root: sudo bash $SELF")"
}

pause() {
  local __rc
  while true; do
    echo
    __rc=0
    read -rp "  ${C_DIM}$(T "ENTER to go back..." "ENTER para voltar...")${C_RESET} " _ || __rc=$?
    # Ctrl+C / signal → just re-prompt (do not leave the menu or crash)
    (( __rc > 128 )) && { echo; continue; }
    break
  done
}

confirm() {
  local ans __rc=0
  read -rp "  $1 $(T "[y/N]" "[s/N]") " ans || __rc=$?
  (( __rc > 128 )) && return 1
  ans="${ans,,}"
  [[ "$ans" == "s" || "$ans" == "sim" || "$ans" == "y" || "$ans" == "yes" ]]
}

# Reads one line into VAR. Returns 0 = ok, 1 = EOF (terminal closed / Ctrl+D),
# 2 = interrupted (Ctrl+C). Menus use this so they never spin in an endless loop.
ask() { # ask VAR "prompt"
  local __rc=0
  read -rp "$2" "$1" || __rc=$?
  (( __rc == 0 )) && return 0
  echo
  (( __rc > 128 )) && return 2
  return 1
}

# Wait for ENTER while the user copies text. Ctrl+C only re-prompts (never exits).
# Aguarda ENTER enquanto o usuário copia. Ctrl+C só reexibe o prompt (nunca sai).
aguardar_copia() {
  local __rc msg
  msg="${1:-$(T "Copy the lines above (select with the mouse). Ctrl+C here does nothing — press ENTER when done." "Copie as linhas acima (selecione com o mouse). Ctrl+C aqui não faz nada — ENTER quando terminar.")}"
  while true; do
    echo
    echo "  ${C_DIM}${msg}${C_RESET}"
    __rc=0
    read -rp "  ${C_BOLD}$(T "ENTER to continue..." "ENTER para continuar...")${C_RESET} " _ || __rc=$?
    (( __rc > 128 )) && { echo; continue; }
    break
  done
}

# Ctrl+C doesn't close the menu: it only interrupts the current task
trap 'echo' INT
# Only restore cursor if the terminal actually supports it (avoids "unknown terminal type")
trap '[[ -t 1 ]] && tput cnorm 2>/dev/null || true' EXIT
_tput() { tput "$@" 2>/dev/null || true; }

# Runs a command in the background showing a spinner, elapsed time and the last log line.
# usage: run_spin "message" /path/log command args...
run_spin() {
  local msg="$1" logf="$2"; shift 2
  mkdir -p "$(dirname "$logf")" 2>/dev/null || true
  : > "$logf"
  "$@" >"$logf" 2>&1 &
  local pid=$! start=$SECONDS i=0 el last w
  trap 'kill "$pid" 2>/dev/null; _tput cnorm' INT
  if [[ -t 1 ]]; then
    _tput civis
    w=$(( COLS - ${#msg} - 16 )); (( w < 10 )) && w=10
    while kill -0 "$pid" 2>/dev/null; do
      el=$((SECONDS - start))
      last="$(tail -n1 "$logf" 2>/dev/null | tr -d '\r' | tr -cd '[:print:]' | cut -c1-"$w")"
      printf '\r\033[K  %s%s%s %s %s[%02d:%02d]%s %s%s%s' \
        "$C_CYAN" "${SPIN[i % ${#SPIN[@]}]}" "$C_RESET" "$msg" \
        "$C_DIM" $((el / 60)) $((el % 60)) "$C_RESET" "$C_DIM" "$last" "$C_RESET"
      i=$((i + 1))
      sleep 0.2
    done
    printf '\r\033[K'
    _tput cnorm
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
    err "$msg $(T "failed (exit code $rc). Last log lines:" "falhou (código $rc). Últimas linhas do log:")"
    tail -n 15 "$logf" 2>/dev/null | sed 's/^/      /' >&2
    echo "      ${C_DIM}$(T "full log" "log completo"): $logf${C_RESET}" >&2
  fi
  return "$rc"
}

# -----------------------------------------------------------------------------
# Utilities / Utilidades
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
  printf '%s' "${ip:-$(T "VPS_IP" "IP_DA_VPS")}"
}

env_get() { # env_get KEY  (strips optional CRLF / quotes)
  [[ -f "$ENV_FILE" ]] || return 0
  local val
  val="$(grep -E "^$1=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '\r' | sed -e 's/^"//' -e 's/"$//')"
  printf '%s' "$val"
}

env_set() { # env_set KEY VALUE  (safe for any character; normalizes line endings)
  local k="$1" v="$2" tmp
  # umask 077: if .env does not exist yet, it is created already restricted (600)
  (
    umask 077
    tmp="$(mktemp)"
    grep -v "^${k}=" "$ENV_FILE" 2>/dev/null | tr -d '\r' > "$tmp" || true
    printf '%s=%s\n' "$k" "$v" >> "$tmp"
    cat "$tmp" > "$ENV_FILE"
    rm -f "$tmp"
  )
  chmod 600 "$ENV_FILE" 2>/dev/null || true
}

container_name() {
  local n; n="$(env_get CONTAINER_NAME)"
  printf '%s' "${n:-mt}"
}

# "env -u TZ": a TZ exported in the host shell would override the .env value
dc() { env -u TZ docker compose -f "$COMPOSE_FILE" "$@"; }

container_running() {
  [[ -f "$COMPOSE_FILE" ]] || return 1
  dc ps -q --status running 2>/dev/null | grep -q .
}

need_base() {
  if [[ ! -f "$COMPOSE_FILE" ]]; then
    err "$(T "Base not installed yet. Use option 1 (or A) first." "Base ainda não instalada. Use a opção 1 (ou A) primeiro.")"
    return 1
  fi
}

# Waits for the container's supervisord to answer (the socket existing is enough)
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
    printf '\r\033[K  %s %s %s (%ds)' "${SPIN[i % ${#SPIN[@]}]}" "$(T "waiting for healthcheck..." "aguardando healthcheck...")" "$st" $((i * 5))
    sleep 5
  done
  printf '\r\033[K'
  return 1
}

# State of one terminal for the dashboard
term_state() { # term_state mt4|mt5
  local id="$1" marker="$APP_DIR/data/prefix-${1}/.mt_exe_path"
  if [[ ! -s "$marker" ]]; then
    badge off "${id^^} $(T "not installed" "não instalado")"; return
  fi
  if container_running; then
    local line
    line="$(dc exec -T mt mt-sv status "$id" 2>/dev/null | head -1 || true)"
    case "$line" in
      *RUNNING*)  badge ok  "${id^^} $(T "running" "rodando")" ;;
      *STARTING*) badge warn "${id^^} $(T "starting" "iniciando")" ;;
      *)          badge err "${id^^} $(T "stopped" "parado")" ;;
    esac
  else
    badge off "${id^^} $(T "installed (container stopped)" "instalado (container parado)")"
  fi
}

painel() {
  local d c mem
  if command -v docker >/dev/null 2>&1; then d="$(badge ok "Docker")"; else d="$(badge off "$(T "Docker missing" "Docker ausente")")"; fi
  if [[ ! -f "$COMPOSE_FILE" ]]; then
    c="$(badge off "$(T "base not installed" "base não instalada")")"
  elif container_running; then
    local st; st="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$(container_name)" 2>/dev/null || echo ?)"
    case "$st" in
      healthy)  c="$(badge ok "$(T "container healthy" "container saudável")")" ;;
      starting) c="$(badge warn "$(T "container starting" "container iniciando")")" ;;
      *)        c="$(badge warn "container: $st")" ;;
    esac
  else
    c="$(badge err "$(T "container stopped" "container parado")")"
  fi
  mem="$(awk '/^MemTotal:/{t=$2}/^MemAvailable:/{a=$2}END{printf "%d/%d MB", a/1024, t/1024}' /proc/meminfo) $(T "free" "livres")"
  echo "  $d    $c    ${C_DIM}RAM $mem${C_RESET}"
  if [[ -f "$COMPOSE_FILE" ]]; then
    echo "  $(term_state mt4)    $(term_state mt5)"
  fi
}

# -----------------------------------------------------------------------------
# Access info / Informações de acesso
# -----------------------------------------------------------------------------
mostrar_acesso() {
  local pw cn tz ip
  pw="$(env_get VNC_PASSWORD)"; pw="${pw:0:8}"; cn="$(container_name)"; tz="$(env_get TZ)"
  ip="$(server_ip)"
  echo "  ${C_BOLD}$(T "MetaTrader access (noVNC)" "Acesso ao MetaTrader (noVNC)")${C_RESET}"
  rule
  echo "  Container:   $cn"
  echo "  $(T "Timezone (TZ):" "Fuso (TZ):  ") ${tz:-?}"
  echo "  $(T "VNC password:" "Senha VNC:   ") ${C_YELLOW}${pw:-$(T "(see .env)" "(veja .env)")}${C_RESET}"
  echo
  echo "  $(T "noVNC is closed to the internet (127.0.0.1 only). To access it," "O noVNC fica fechado para a internet (só 127.0.0.1). Para acessar,")"
  echo "  $(T "open an SSH tunnel" "abra um túnel SSH") ${C_BOLD}$(T "on your computer" "no seu computador")${C_RESET} (Windows/Mac/Linux):"
  echo
  echo "    ${C_CYAN}ssh -N -p $SSH_PORT -L 6080:127.0.0.1:6080 root@$ip${C_RESET}"
  echo
  echo "  $(T "and open in your browser:" "e abra no navegador:")"
  echo
  echo "    ${C_CYAN}http://localhost:6080/vnc.html?autoconnect=1&resize=scale${C_RESET}"
  echo
  echo "  ${C_DIM}$(T "Tip: keep the tunnel terminal open while you use noVNC." "Dica: o terminal do túnel precisa ficar aberto enquanto você usa o noVNC.")${C_RESET}"
}

# Clear the screen and show ONLY the access block, then wait for ENTER (Ctrl+C safe).
# Limpa a tela e mostra SÓ o bloco de acesso, depois aguarda ENTER (seguro com Ctrl+C).
mostrar_acesso_limpo() {
  clear 2>/dev/null || true
  echo
  mostrar_acesso
  echo
  rule
  aguardar_copia
}

# -----------------------------------------------------------------------------
# Timezone / Fuso horário
# -----------------------------------------------------------------------------
escolher_tz() {
  local atual opt chosen="America/Sao_Paulo" bad=0
  atual="$(env_get TZ)"; atual="${atual:-America/Sao_Paulo}"
  echo "  ${C_BOLD}$(T "Container timezone" "Fuso horário do container")${C_RESET} ${C_DIM}($(T "current" "atual"): $atual)${C_RESET}"
  echo "    1) America/Sao_Paulo  ($(T "Brazil default" "padrão BR"))"
  echo "    2) UTC"
  echo "    3) $(T "Use this machine's timezone" "Usar o da máquina")"
  echo "    4) $(T "Other (type it, e.g. Europe/London)" "Outro (digitar, ex: Europe/London)")"
  echo "    5) $(T "Keep the current one" "Manter o atual")"
  read -rp "  $(T "Option" "Opção") [1-5] (Enter=5): " opt || true
  case "${opt:-5}" in
    1) chosen="America/Sao_Paulo" ;;
    2) chosen="UTC" ;;
    3)
      if [[ -f /etc/timezone ]]; then chosen="$(tr -d '[:space:]' < /etc/timezone)"
      elif command -v timedatectl >/dev/null 2>&1; then chosen="$(timedatectl show -p Timezone --value 2>/dev/null || true)"
      fi
      chosen="${chosen:-America/Sao_Paulo}" ;;
    4)
      read -rp "  $(T "Type the TZ: " "Digite o TZ: ")" chosen || true
      chosen="${chosen:-$atual}" ;;
    *) chosen="$atual" ;;
  esac
  # The host may not have tzdata installed (the container does), so only check the
  # zoneinfo file when the directory exists; always check the name's format.
  if [[ ! "$chosen" =~ ^[A-Za-z0-9_+-]+(/[A-Za-z0-9_+-]+)*$ ]]; then
    bad=1
  elif [[ "$chosen" != "UTC" && -d /usr/share/zoneinfo && ! -e "/usr/share/zoneinfo/$chosen" ]]; then
    bad=1
  fi
  if (( bad )); then
    warn "$(T "TZ '$chosen' is not valid; keeping $atual" "TZ '$chosen' não é válido; mantendo $atual")"
    chosen="$atual"
  fi
  env_set TZ "$chosen"
  ok "TZ=$chosen"
}

# -----------------------------------------------------------------------------
# Wine version / Versão do Wine
# -----------------------------------------------------------------------------
escolher_wine() {
  local atual def=1 opt v
  atual="$(env_get WINE_VERSION)"; atual="${atual:-10.0.0.0~jammy-1}"
  [[ "$atual" == 11.* ]] && def=2
  echo "  ${C_BOLD}$(T "Wine version" "Versão do Wine")${C_RESET} ${C_DIM}($(T "current" "atual"): ${atual%%.*})${C_RESET}"
  echo "    1) Wine 10  ${C_GREEN}($(T "recommended" "recomendado"))${C_RESET}  ${C_DIM}— $(T "works with the official MetaQuotes installer" "funciona com o instalador oficial da MetaQuotes")${C_RESET}"
  echo "    2) Wine 11  ${C_DIM}— $(T "newer; the official MetaQuotes installer may fail" "mais novo; o instalador oficial da MetaQuotes pode falhar")${C_RESET}"
  read -rp "  $(T "Option" "Opção") [1-2] (Enter=$def): " opt || true
  case "${opt:-$def}" in
    2) v="11.0.0.0~jammy-1" ;;
    *) v="10.0.0.0~jammy-1" ;;
  esac
  env_set WINE_VERSION "$v"
  ok "Wine ${v%%.*} (WINE_VERSION=$v)"
}

# -----------------------------------------------------------------------------
# Project file generation / Geração dos arquivos do projeto
# -----------------------------------------------------------------------------
gerar_arquivos() {
  mkdir -p "$APP_DIR"/{docker/bin,docker/lib,scripts,data/{prefix-mt4,prefix-mt5,logs,installers}}

  cat > "$APP_DIR/.dockerignore" <<'EOF'
data/
backups/
scripts/
EAs/
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
# Use a recent winetricks so vcrun2019 / Microsoft redistributable SHA256 matches
ARG WINETRICKS_VERSION=master
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
        procps tzdata fonts-liberation \
        libgnutls30 libgnutls30:i386 \
        libfreetype6 libfreetype6:i386 \
        libfontconfig1 libfontconfig1:i386 \
        winbind; \
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
      MT_LANG: "${MT_LANG:-en}"
      RESOLUTION: "${RESOLUTION:-1024x600x16}"
      VNC_PASSWORD: "${VNC_PASSWORD:?VNC_PASSWORD is not set / não definida; run scripts/setup-host.sh}"
      EA_DEPS_MT4: "${EA_DEPS_MT4:-corefonts vcrun2019 winhttp gdiplus msxml6}"
      EA_DEPS_MT5: "${EA_DEPS_MT5:-corefonts vcrun2019 winhttp gdiplus msxml6}"
      MT4_ARCH: "${MT4_ARCH:-win64}"

    volumes:
      - ./data/prefix-mt4:/home/mt/prefix/mt4
      - ./data/prefix-mt5:/home/mt/prefix/mt5
      - ./data/logs:/home/mt/logs
      - ./data/installers:/home/mt/installers:ro

    # /tmp in RAM (tmpfs): /tmp/vnc.pass (VNC password) is never written to disk.
    # Also holds supervisor.sock and the temporary installer; counts toward mem_limit only while used.
    tmpfs:
      - /tmp:size=128m,mode=1777,uid=1000,gid=1000

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

# L "english" "português" → message in the language set by MT_LANG (en|pt)
MT_LANG="${MT_LANG:-en}"
L() { if [[ "$MT_LANG" == pt* ]]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }

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
    log WARN retry "$(L "attempt $i/$n failed: $*" "tentativa $i/$n falhou: $*")"
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
      # The current mt4setup.exe installs MT5; the real MT4 installer is mt4oldsetup.exe
      # (the same one MetaQuotes' own mt4ubuntu.sh downloads). A broker installer placed
      # in /home/mt/installers/ still takes priority (see --installer / host menu).
      MT_URL="https://download.mql5.com/cdn/web/metaquotes.software.corp/mt4/mt4oldsetup.exe"
      MT_DEPS="${EA_DEPS_MT4:-$default_deps}" ;;
    mt5)
      MT_ID=mt5; MT_NAME="MetaTrader 5"; MT_ARCH="win64"; MT_EXE_NAME="terminal64.exe"
      MT_URL="https://download.mql5.com/cdn/web/metaquotes.software.corp/mt5/mt5setup.exe"
      MT_DEPS="${EA_DEPS_MT5:-$default_deps}" ;;
    *) die lib "$(L "invalid terminal: '${1:-}'" "terminal inválido: '${1:-}'")" ;;
  esac
  export WINEPREFIX="/home/mt/prefix/$MT_ID"
  export WINEARCH="$MT_ARCH"
  MT_MARKER="$WINEPREFIX/.mt_exe_path"
}

find_exe() {
  # Prefer the expected name; for MT4 also accept terminal64.exe only as a last resort
  # (so we can warn that the official installer delivered MT5 instead of MT4).
  local found
  found="$(find "$WINEPREFIX/drive_c" -maxdepth 6 -type f -iname "$MT_EXE_NAME" \
       -not -ipath '*/windows/*' -print -quit 2>/dev/null || true)"
  if [[ -n "$found" ]]; then
    printf '%s' "$found"
    return 0
  fi
  if [[ "$MT_ID" == "mt4" ]]; then
    found="$(find "$WINEPREFIX/drive_c" -maxdepth 6 -type f -iname 'terminal64.exe' \
         -not -ipath '*/windows/*' -print -quit 2>/dev/null || true)"
    if [[ -n "$found" ]]; then
      log WARN install "$(L \
        "found terminal64.exe instead of terminal.exe — the installer delivered MT5. Use mt4oldsetup.exe or a broker MT4 installer (place it in data/installers/ and re-run with --installer)" \
        "encontrado terminal64.exe em vez de terminal.exe — o instalador entregou o MT5. Use o mt4oldsetup.exe ou um instalador MT4 de corretora (coloque em data/installers/ e rode com --installer)")"
    fi
  fi
  printf '%s' "$found"
}
EOF

  cat > "$APP_DIR/docker/bin/mt-entrypoint" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source /opt/mt/lib/common.sh
COMP="entrypoint"

log INFO "$COMP" "$(L "starting (uid=$(id -u))" "iniciando (uid=$(id -u))")"

for d in /home/mt/prefix/mt4 /home/mt/prefix/mt5 /home/mt/logs; do
  [[ -w "$d" ]] || die "$COMP" "$(L \
    "no write permission on $d. On the host run: chown -R 1000:1000 <APP_DIR>/data" \
    "sem permissão de escrita em $d. No host: chown -R 1000:1000 <APP_DIR>/data")"
done

[[ -n "${VNC_PASSWORD:-}" ]] || die "$COMP" "$(L "VNC_PASSWORD is empty. Run scripts/setup-host.sh" "VNC_PASSWORD vazia. Rode scripts/setup-host.sh")"
(( ${#VNC_PASSWORD} >= 8 )) || die "$COMP" "$(L "VNC_PASSWORD needs at least 8 characters" "VNC_PASSWORD precisa de pelo menos 8 caracteres")"
if (( ${#VNC_PASSWORD} > 8 )); then
  log WARN "$COMP" "$(L "VNC_PASSWORD has ${#VNC_PASSWORD} chars; x11vnc only uses the first 8" "VNC_PASSWORD tem ${#VNC_PASSWORD} chars; x11vnc usa só os 8 primeiros")"
  VNC_PASSWORD="${VNC_PASSWORD:0:8}"
fi
( umask 077; printf '%s\n' "$VNC_PASSWORD" > /tmp/vnc.pass )
chmod 600 /tmp/vnc.pass 2>/dev/null || true
unset VNC_PASSWORD

# /tmp is a tmpfs (compose), so the image's /tmp/.X11-unix is hidden: recreate it
mkdir -p /tmp/.X11-unix && chmod 1777 /tmp/.X11-unix 2>/dev/null || true
rm -f /tmp/.X99-lock /tmp/.X11-unix/X99 /tmp/supervisor.sock /tmp/supervisord.pid

LIMIT="$(mem_limit_mb)"
log INFO "$COMP" "$(L "effective memory limit: ${LIMIT}MB" "limite de memória efetivo: ${LIMIT}MB")"
(( LIMIT >= 700 )) || log WARN "$COMP" "$(L "memory < 700MB: MT5 + Wine may hit OOM" "memória < 700MB: MT5 + Wine podem sofrer OOM")"

export RESOLUTION="${RESOLUTION:-1024x600x16}"
log INFO "$COMP" "$(L "starting supervisord (resolution $RESOLUTION)" "iniciando supervisord (resolução $RESOLUTION)")"
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
  # Still waiting for the installation: nothing to shut down (and we must not
  # start Wine here, it would create a prefix from scratch).
  if [[ -z "$WPID" ]]; then
    log INFO "$COMP" "$(L "SIGTERM received before $MT_NAME started: exiting" "SIGTERM recebido antes de iniciar $MT_NAME: saindo")"
    exit 0
  fi
  log INFO "$COMP" "$(L "SIGTERM received: shutting $MT_NAME down gracefully" "SIGTERM recebido: encerrando $MT_NAME com graça")"
  WINEPREFIX="$WINEPREFIX" wine taskkill /IM "$MT_EXE_NAME" 2>/dev/null || true
  kill -TERM "$WPID" 2>/dev/null || true
  # Keep well under supervisord stopwaitsecs so we finish before SIGKILL
  for _ in $(seq 1 25); do
    kill -0 "$WPID" 2>/dev/null || break
    sleep 1
  done
  # Always kill wineserver for this prefix (avoids orphans and hung -w)
  WINEPREFIX="$WINEPREFIX" wineserver -k 2>/dev/null || true
  wait "$WPID" 2>/dev/null || true
  timeout 15 env WINEPREFIX="$WINEPREFIX" wineserver -w 2>/dev/null || true
  exit 0
}
trap stop TERM INT

n=0
until [[ -s "$MT_MARKER" ]]; do
  if (( n % 30 == 0 )); then
    log WARN "$COMP" "$(L "$MT_NAME is not installed. Run: docker compose exec mt mt-install $ID" "$MT_NAME não instalado. Rode: docker compose exec mt mt-install $ID")"
  fi
  n=$((n + 1))
  sleep 10 & wait $!
done

EXE="$(<"$MT_MARKER")"
[[ -f "$EXE" ]] || die "$COMP" "$(L "executable not found: $EXE (reinstall: mt-install $ID --force)" "executável não existe: $EXE (reinstale: mt-install $ID --force)")"

log INFO "$COMP" "$(L "starting $MT_NAME: $EXE" "iniciando $MT_NAME: $EXE")"
cd "$(dirname "$EXE")"
wine "$EXE" /portable &
WPID=$!

rc=0
wait "$WPID" || rc=$?
# LiveUpdate: the original process exits after launching the updated binary.
# Wait until no terminal remains for this prefix before exiting, so supervisor
# does not start a second concurrent instance.
for _ in $(seq 1 30); do
  if ! pgrep -fi "$MT_EXE_NAME" >/dev/null 2>&1; then
    break
  fi
  # If a new instance appeared under the same prefix, treat as LiveUpdate success
  # and keep waiting for it to settle rather than exiting immediately.
  sleep 2
done
timeout 20 env WINEPREFIX="$WINEPREFIX" wineserver -w 2>/dev/null || true
log WARN "$COMP" "$(L "$MT_NAME exited (rc=$rc); supervisor will restart it" "$MT_NAME encerrou (rc=$rc); supervisor vai reiniciar")"
sleep 5
exit "$rc"
EOF

  cat > "$APP_DIR/docker/bin/mt-install" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source /opt/mt/lib/common.sh
COMP="install"

usage() {
  L "Usage: mt-install mt4|mt5 [--force] [--skip-deps] [--installer PATH]" \
    "Uso: mt-install mt4|mt5 [--force] [--skip-deps] [--installer CAMINHO]"
  echo
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
    *) usage; die "$COMP" "$(L "unknown option: $1" "opção desconhecida: $1")" ;;
  esac
  shift
done

load_terminal "$ID"

RUNFLAG=/tmp/mt-install.running
if [[ -f "$RUNFLAG" ]] && kill -0 "$(cat "$RUNFLAG")" 2>/dev/null; then
  die "$COMP" "$(L "another installation is in progress" "outra instalação em andamento")"
fi
echo $$ > "$RUNFLAG"
INSTALLER="/tmp/mt-setup-$ID.exe"
# Helper: kill wineserver for this prefix and wait (with timeout) so we never hang.
wineserver_kill_wait() {
  WINEPREFIX="$WINEPREFIX" wineserver -k 2>/dev/null || true
  timeout 30 env WINEPREFIX="$WINEPREFIX" wineserver -w 2>/dev/null || true
}

# pgrep limited to processes that belong to this WINEPREFIX (avoid cross-prefix false positives)
prefix_pgrep() {
  local name="$1" pid cwd
  for pid in $(pgrep -fi "$name" 2>/dev/null || true); do
    cwd="$(readlink -f /proc/$pid/cwd 2>/dev/null || true)"
    [[ "$cwd" == "$WINEPREFIX"* || "$cwd" == *"/prefix/$MT_ID"* ]] && return 0
  done
  # Fallback: any process whose environ mentions this WINEPREFIX
  for pid in $(pgrep -fi "$name" 2>/dev/null || true); do
    if tr '\0' '\n' < /proc/$pid/environ 2>/dev/null | grep -q "WINEPREFIX=$WINEPREFIX"; then
      return 0
    fi
  done
  return 1
}

cleanup() {
  rm -f "$RUNFLAG" "$INSTALLER"
  if ! prefix_pgrep "${MT_EXE_NAME:-terminal}"; then
    wineserver_kill_wait
  fi
}
trap cleanup EXIT
trap 'log ERROR "$COMP" "$(L "failed at line $LINENO" "falha na linha $LINENO")"' ERR

LIMIT="$(mem_limit_mb)"
(( LIMIT >= 600 )) || die "$COMP" "$(L "memory limit (${LIMIT}MB) < 600MB" "limite de memória (${LIMIT}MB) < 600MB")"
xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 || die "$COMP" "$(L "display $DISPLAY unavailable" "display $DISPLAY indisponível")"

if [[ -s "$MT_MARKER" && $FORCE -eq 0 ]]; then
  log INFO "$COMP" "$(L "$MT_NAME already installed: nothing to do" "$MT_NAME já instalado: nada a fazer")"
  exit 0
fi
if (( FORCE )) && prefix_pgrep "$MT_EXE_NAME"; then
  die "$COMP" "$(L "$MT_NAME is running. Stop it: mt-sv stop $ID" "$MT_NAME em execução. Pare: mt-sv stop $ID")"
fi
if (( FORCE )); then rm -f "$MT_MARKER"; fi

if [[ ! -f "$WINEPREFIX/.mt_prefix_ready" ]]; then
  log INFO "$COMP" "$(L "creating $MT_ARCH prefix" "criando prefixo $MT_ARCH")"
  WINEDLLOVERRIDES="mscoree,mshtml=d;winemenubuilder.exe=d" timeout 300 wineboot --init
  wineserver_kill_wait
  touch "$WINEPREFIX/.mt_prefix_ready"
fi

if (( SKIP_DEPS == 0 )); then
  mkdir -p "$WINEPREFIX/.deps"
  failed=()
  for dep in $MT_DEPS; do
    if [[ -f "$WINEPREFIX/.deps/$dep" ]]; then
      log INFO deps "$(L "$dep already installed" "$dep já instalado")"; continue
    fi
    log INFO deps "$(L "installing $dep" "instalando $dep")"
    if retry 2 10 timeout 2400 winetricks -q "$dep"; then
      touch "$WINEPREFIX/.deps/$dep"
    elif retry 1 5 timeout 2400 winetricks --force -q "$dep"; then
      # SHA256 of Microsoft redistributables changes; --force bypasses the checksum
      touch "$WINEPREFIX/.deps/$dep"
      log WARN deps "$(L "$dep installed with --force (checksum mismatch)" "$dep instalado com --force (checksum divergente)")"
    else
      failed+=("$dep")
      log ERROR deps "$(L "failed: $dep" "falhou: $dep")"
      log WARN deps "$(L "if Microsoft's URL changed, try updating WINETRICKS_VERSION in the Dockerfile" "se a URL da Microsoft mudou, tente atualizar WINETRICKS_VERSION no Dockerfile")"
    fi
    wineserver_kill_wait
  done
  if [[ ! -f "$WINEPREFIX/.deps/win10" ]]; then
    if winetricks -q win10; then touch "$WINEPREFIX/.deps/win10"; fi
    wineserver_kill_wait
  fi
  if ((${#failed[@]} > 0)); then
    log WARN deps "$(L "failed: ${failed[*]}" "falharam: ${failed[*]}")"
  fi
fi

if [[ -n "$LOCAL_INSTALLER" ]]; then
  [[ -f "$LOCAL_INSTALLER" ]] || die "$COMP" "$(L "installer not found: $LOCAL_INSTALLER" "instalador não encontrado: $LOCAL_INSTALLER")"
  cp "$LOCAL_INSTALLER" "$INSTALLER"
else
  log INFO "$COMP" "$(L "downloading $MT_URL" "baixando $MT_URL")"
  retry 3 5 wget --timeout=30 --tries=1 -q -O "$INSTALLER" "$MT_URL" || die "$COMP" "$(L "download failed" "download falhou")"
fi
size="$(stat -c %s "$INSTALLER")"
(( size >= 200000 )) || die "$COMP" "$(L "installer too small (${size} bytes)" "instalador pequeno demais (${size} bytes)")"
[[ "$(head -c2 "$INSTALLER")" == "MZ" ]] || die "$COMP" "$(L "header is not a Windows executable (MZ)" "cabeçalho não é executável Windows (MZ)")"

log INFO "$COMP" "$(L "running the installer (watch it through noVNC)" "executando instalador (acompanhe pelo noVNC)")"
timeout 900 wine "$INSTALLER" /auto >> "$LOG_DIR/setup-$ID.log" 2>&1 &
SETUP_PID=$!
terminal_seen=0
MSG_STARTED="$(L "terminal started; waiting 90s for MQL/data extraction" "terminal iniciou; aguardando 90s para extração MQL/bases")"
# Also watch for the alternate name (official mt4setup may launch terminal64.exe)
_alt_name=""
[[ "$MT_ID" == "mt4" ]] && _alt_name="terminal64.exe"
for ((i = 0; i < 180; i++)); do
  if prefix_pgrep "$MT_EXE_NAME" || { [[ -n "$_alt_name" ]] && prefix_pgrep "$_alt_name"; }; then
    log INFO "$COMP" "$MSG_STARTED"
    sleep 90
    terminal_seen=1
    break
  fi
  if ! kill -0 "$SETUP_PID" 2>/dev/null; then
    log INFO "$COMP" "$(L "installer exited; waiting up to 60s for the terminal" "instalador encerrou; aguardando terminal por até 60s")"
    for ((j = 0; j < 12; j++)); do
      if prefix_pgrep "$MT_EXE_NAME" || { [[ -n "$_alt_name" ]] && prefix_pgrep "$_alt_name"; }; then
        log INFO "$COMP" "$MSG_STARTED"
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
(( terminal_seen )) || log WARN "$COMP" "$(L "terminal not detected in time" "terminal não detectado no prazo")"

if kill -0 "$SETUP_PID" 2>/dev/null; then
  kill -TERM "$SETUP_PID" 2>/dev/null || true
  sleep 3
  wait "$SETUP_PID" 2>/dev/null || true
fi

EXE="$(find_exe || true)"
if [[ -z "$EXE" ]]; then
  find "$WINEPREFIX/drive_c" -iname 'terminal*.exe' 2>/dev/null | head -20 >> "$LOG_DIR/setup-$ID.log" || true
  if [[ "$MT_ID" == "mt4" ]]; then
    die "$COMP" "$(L \
      "terminal.exe not found. The installer may have delivered MT5. Place mt4oldsetup.exe or a real MT4 broker installer in /home/mt/installers/ and re-run: mt-install mt4 --installer /home/mt/installers/YOURFILE.exe (see $LOG_DIR/setup-$ID.log)" \
      "terminal.exe não encontrado. O instalador pode ter entregado o MT5. Coloque o mt4oldsetup.exe ou um instalador real de MT4 de corretora em /home/mt/installers/ e rode: mt-install mt4 --installer /home/mt/installers/SEUARQUIVO.exe (veja $LOG_DIR/setup-$ID.log)")"
  fi
  die "$COMP" "$(L "$MT_EXE_NAME not found (see $LOG_DIR/setup-$ID.log)" "$MT_EXE_NAME não encontrado (veja $LOG_DIR/setup-$ID.log)")"
fi

# Always kill leftover Wine processes for this prefix so wineserver -w cannot hang forever
if prefix_pgrep "$MT_EXE_NAME" || { [[ -n "$_alt_name" ]] && prefix_pgrep "$_alt_name"; }; then
  log INFO "$COMP" "$(L "closing the leftover terminal to hand over to the supervisor" "fechando terminal órfão para entrega ao supervisor")"
  WINEPREFIX="$WINEPREFIX" wine taskkill /IM "$MT_EXE_NAME" 2>/dev/null || true
  [[ -n "$_alt_name" ]] && WINEPREFIX="$WINEPREFIX" wine taskkill /IM "$_alt_name" 2>/dev/null || true
  for _ in $(seq 1 20); do
    prefix_pgrep "$MT_EXE_NAME" || { [[ -n "$_alt_name" ]] && prefix_pgrep "$_alt_name"; } || break
    sleep 1
  done
fi
# Unconditional kill+wait (with timeout) — prevents the infinite wineserver -w deadlock
wineserver_kill_wait
sleep 2
echo "$EXE" > "$MT_MARKER"
chmod 700 "$WINEPREFIX"
rm -rf "$HOME/.cache/winetricks" "$HOME/.cache/fontconfig"
log INFO "$COMP" "$(L "$MT_NAME installed: $EXE" "$MT_NAME instalado: $EXE")"
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
command=bash -c "rm -f /tmp/.X99-lock /tmp/.X11-unix/X99; exec Xvfb :99 -screen 0 %(ENV_RESOLUTION)s -ac -nolisten tcp -noreset"
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
stopwaitsecs=60
stopasgroup=true
killasgroup=true
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
stopwaitsecs=60
stopasgroup=true
killasgroup=true
redirect_stderr=true
stdout_logfile=/dev/stdout
stdout_logfile_maxbytes=0
EOF

  cat > "$APP_DIR/scripts/setup-host.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
umask 077   # any file created here (.env, swap, etc.) is born restricted
APP_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$APP_DIR/.env"

# UI language (saved by the main script in $APP_DIR/.lang)
LANG_UI="en"
if [[ -r "$APP_DIR/.lang" ]]; then LANG_UI="$(<"$APP_DIR/.lang")"; fi
[[ "$LANG_UI" == "pt" ]] || LANG_UI="en"
L() { if [[ "$LANG_UI" == "pt" ]]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }

log() { echo "$(date '+%Y-%m-%dT%H:%M:%S%z') [$1] [setup-host] ${*:2}"; }
die() { log ERROR "$*"; exit 1; }

[[ $EUID -eq 0 ]] || die "$(L "run as root: sudo $0" "execute como root: sudo $0")"
command -v docker >/dev/null 2>&1 || die "$(L "Docker not found" "Docker não encontrado")"
docker compose version >/dev/null 2>&1 || die "$(L "Docker Compose v2 not found" "Docker Compose v2 não encontrado")"

TOTAL_MB="$(awk '/^MemTotal:/{print int($2/1024)}' /proc/meminfo)"
SWAP_MB="$(awk '/^SwapTotal:/{print int($2/1024)}' /proc/meminfo)"
AVAIL_MB="$(awk '/^MemAvailable:/{print int($2/1024)}' /proc/meminfo)"
CORES="$(nproc)"
if   (( TOTAL_MB <= 2048 )); then SWAP_TARGET=2048
elif (( TOTAL_MB <= 4096 )); then SWAP_TARGET=1024
else SWAP_TARGET=0; fi
log INFO "RAM=${TOTAL_MB}MB available=${AVAIL_MB}MB swap=${SWAP_MB}MB cpus=${CORES}"

if (( AVAIL_MB < 800 )); then
  log WARN "$(L "MemAvailable=${AVAIL_MB}MB < 800MB: the VPS is overloaded right now; the container may start slowly or hit a temporary OOM" "MemAvailable=${AVAIL_MB}MB < 800MB: VPS sobrecarregada agora; container pode iniciar lento ou sofrer OOM temporário")"
fi

make_swapfile() { # make_swapfile MB [dd]
  local mb="$1" mode="${2:-fast}"
  rm -f /swapfile
  if [[ "$mode" == "fast" ]]; then
    fallocate -l "${mb}M" /swapfile 2>/dev/null || dd if=/dev/zero of=/swapfile bs=1M count="$mb" status=none
  else
    dd if=/dev/zero of=/swapfile bs=1M count="$mb" status=none
  fi
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
}
if (( SWAP_TARGET > 0 && SWAP_MB < SWAP_TARGET - 100 )); then
  NEED=$(( SWAP_TARGET - SWAP_MB ))
  if swapon --show=NAME --noheadings 2>/dev/null | grep -qx '/swapfile'; then
    log WARN "$(L "/swapfile is already active but small (${SWAP_MB}MB); not recreating it while in use" "/swapfile já está ativo mas é pequeno (${SWAP_MB}MB); não vou recriá-lo em uso")"
  else
    log INFO "$(L "creating ${NEED}MB of swap" "criando swap de ${NEED}MB")"
    [[ -f /swapfile ]] || make_swapfile "$NEED"
    SWAP_OK=0
    if swapon /swapfile 2>/dev/null; then
      SWAP_OK=1
    else
      # fallocate-made swapfiles don't work on some filesystems: retry with dd
      make_swapfile "$NEED" dd
      if swapon /swapfile 2>/dev/null; then SWAP_OK=1; else log WARN "$(L "swapon failed (OpenVZ/LXC?)" "swapon falhou (OpenVZ/LXC?)")"; fi
    fi
    # only persist in fstab when swap really works (a broken entry only causes boot noise)
    if (( SWAP_OK )); then
      grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi
    SWAP_MB="$(awk '/^SwapTotal:/{print int($2/1024)}' /proc/meminfo)"
  fi
fi

cat > /etc/sysctl.d/99-mt-docker.conf <<'SYS'
vm.swappiness=20
vm.vfs_cache_pressure=50
SYS
sysctl -q -p /etc/sysctl.d/99-mt-docker.conf >/dev/null 2>&1 || log WARN "$(L "sysctl not applied" "sysctl não aplicado")"

RESERVE=$(( TOTAL_MB * 15 / 100 )); (( RESERVE >= 200 )) || RESERVE=200
MEM_MB=$(( TOTAL_MB - RESERVE ))
(( MEM_MB >= 600 )) || log WARN "$(L "only ${MEM_MB}MB for the container" "só ${MEM_MB}MB para o container")"
SWAP_ALLOW=$(( SWAP_MB > 2048 ? 2048 : SWAP_MB ))
if (( SWAP_ALLOW == 0 )); then
  SWAP_ALLOW=512
  log WARN "$(L "host has no swap; memswap_limit will use +512 MB of headroom" "host sem swap; memswap_limit usará +512 MB de headroom")"
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
set_kv MT_LANG "$LANG_UI"
# win32 breaks 64-bit installers ("Bad EXE format"); win64 runs both
[[ "$(get_kv MT4_ARCH)" == "win32" ]] && set_kv MT4_ARCH win64

if [[ -z "$(get_kv VNC_PASSWORD)" ]]; then
  PW="$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | cut -c1-8)"
  set_kv VNC_PASSWORD "$PW"
  log INFO "$(L "VNC password generated: $PW (WRITE IT DOWN NOW)" "senha VNC gerada: $PW (ANOTE AGORA)")"
else
  log INFO "$(L "existing VNC password kept" "senha VNC existente preservada")"
fi

# Daily cleanup: logs older than 15 days are deleted; logs over 50MB are truncated
CRON_MARKER="# mt-docker-log-cleanup"
CRON_CMD="0 3 * * * find ${APP_DIR}/data -type f -name '*.log' -mtime +15 -delete; find ${APP_DIR}/data/logs -type f -name '*.log' -size +50M -exec truncate -s 0 {} + ${CRON_MARKER}"
if command -v crontab >/dev/null 2>&1; then
  { crontab -l 2>/dev/null | grep -vF "$CRON_MARKER" || true; echo "$CRON_CMD"; } | crontab -
  log INFO "$(L "log-cleanup cron installed/updated (daily at 03:00)" "cron de limpeza de logs instalado/atualizado (diário 03:00)")"
else
  log WARN "$(L "crontab not available; automatic log cleanup not configured" "crontab não disponível; limpeza automática de logs não configurada")"
fi

log INFO "$(L "limits" "limites"): mem=${MEM_MB}m memswap=${MEMSWAP_MB}m cpus=${CPUS} shm=${SHM}m"
log INFO "$(L "done" "pronto")"
EOF

  cat > "$APP_DIR/scripts/backup.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

LANG_UI="en"
if [[ -r "$ROOT/.lang" ]]; then LANG_UI="$(<"$ROOT/.lang")"; fi
[[ "$LANG_UI" == "pt" ]] || LANG_UI="en"
L() { if [[ "$LANG_UI" == "pt" ]]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }
log() { echo "$(date '+%Y-%m-%dT%H:%M:%S%z') [$1] [backup] ${*:2}"; }

# Folder: BACKUP_DIR > .backup_dir file (written by the menu) > $ROOT/backups
# BACKUP_KEEP=N keeps only the N most recent; default 0 = never delete anything (delete by hand).
KEEP="${BACKUP_KEEP:-0}"
DEST="${BACKUP_DIR:-}"
if [[ -z "$DEST" && -s "$ROOT/.backup_dir" ]]; then DEST="$(<"$ROOT/.backup_dir")"; fi
DEST="${DEST:-$ROOT/backups}"
mkdir -p "$DEST"
TS="$(date +%Y%m%d-%H%M%S)"
OUT="$DEST/mt-backup-$TS.tar.gz"

NEED="$(du -sm data 2>/dev/null | cut -f1 || true)"; NEED="${NEED:-0}"
FREE="$(df -Pm "$DEST" | awk 'NR==2{print $4}')"; FREE="${FREE:-0}"
(( FREE > NEED / 2 )) || { log ERROR "$(L "not enough disk space" "espaço insuficiente")"; exit 1; }

# drive_c (terminal, account, EAs) + Wine registry + installer markers, so the
# backup restores a complete terminal even after it was uninstalled.
TARGETS=()
for p in prefix-mt4 prefix-mt5; do
  [[ -d "data/$p/drive_c" ]] || continue
  TARGETS+=("$p/drive_c")
  for extra in system.reg user.reg userdef.reg .mt_exe_path .mt_prefix_ready .deps dosdevices; do
    if [[ -e "data/$p/$extra" || -L "data/$p/$extra" ]]; then TARGETS+=("$p/$extra"); fi
  done
done
if ((${#TARGETS[@]} == 0)); then
  log WARN "$(L "no prefix found; backup skipped" "nenhum prefixo encontrado; backup ignorado")"
  exit 0
fi

umask 077
log INFO "backup → $OUT (${TARGETS[*]})"
TARERR="$(mktemp)"
rc=0
tar -C data -czf "$OUT" \
    --exclude='Tester' --exclude='tester' \
    --ignore-failed-read \
    "${TARGETS[@]}" 2>"$TARERR" || rc=$?
if (( rc == 1 )); then log WARN "$(L "files changed while being copied" "arquivos mudaram durante a cópia")"; rc=0; fi
if (( rc != 0 )); then
  log ERROR "$(L "tar failed" "tar falhou")"; tail -n 5 "$TARERR" >&2 || true
  rm -f "$OUT" "$TARERR"; exit "$rc"
fi
rm -f "$TARERR"

chown 1000:1000 "$OUT" 2>/dev/null || true
chmod 600 "$OUT"
log INFO "ok: $(du -h "$OUT" | cut -f1)  $OUT"
if (( KEEP > 0 )); then
  ls -1t "$DEST"/mt-backup-*.tar.gz 2>/dev/null | tail -n +"$((KEEP + 1))" | while read -r old; do
    rm -f -- "$old"; log INFO "$(L "removed old backup" "removido antigo"): $old"
  done
fi
EOF

  cat > "$APP_DIR/scripts/update.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"

LANG_UI="en"
if [[ -r "$ROOT/.lang" ]]; then LANG_UI="$(<"$ROOT/.lang")"; fi
[[ "$LANG_UI" == "pt" ]] || LANG_UI="en"
L() { if [[ "$LANG_UI" == "pt" ]]; then printf '%s' "$2"; else printf '%s' "$1"; fi; }
log() { echo "$(date '+%Y-%m-%dT%H:%M:%S%z') [$1] [update] ${*:2}"; }

log INFO "$(L "backup before the update" "backup antes da atualização")"
"$ROOT/scripts/backup.sh"

log INFO "$(L "rebuilding the image" "reconstruindo imagem")"
# env -u TZ: a TZ in the shell would override the one in .env
env -u TZ docker compose build --pull
env -u TZ docker compose up -d
log INFO "$(L "finished" "concluído")"
EOF

  chmod 755 "$APP_DIR"/docker/bin/* "$APP_DIR"/scripts/*.sh
  chmod 644 "$APP_DIR"/docker/lib/common.sh "$APP_DIR"/docker/supervisord.conf \
            "$APP_DIR"/Dockerfile "$APP_DIR"/docker-compose.yml "$APP_DIR"/.dockerignore
}

# Installs the "mt-menu" shortcut (a copy of this script in $APP_DIR/scripts)
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
# Step 1 — Base install / Etapa 1 — Instalação base
# -----------------------------------------------------------------------------
etapa_instalar_base() {
  title "$(T "1 · Base installation" "1 · Instalação base")"
  require_root

  case "$(. /etc/os-release 2>/dev/null; echo "${ID:-?}")" in
    ubuntu|debian) ;;
    *) warn "$(T "This system is not Ubuntu/Debian; the script was designed for them." "Sistema não é Ubuntu/Debian; o script foi pensado para eles.")" ;;
  esac

  if ! command -v curl >/dev/null 2>&1; then
    info "$(T "Installing curl..." "Instalando curl...")"
    apt-get update -qq && apt-get install -y -qq curl ca-certificates \
      || { err "$(T "could not install curl" "não consegui instalar curl")"; return 1; }
  fi

  if ! command -v docker >/dev/null 2>&1; then
    run_spin "$(T "Installing Docker (get.docker.com)" "Instalando Docker (get.docker.com)")" /tmp/mt-docker-install.log \
      bash -c 'curl -fsSL https://get.docker.com | DEBIAN_FRONTEND=noninteractive sh' || return 1
  fi
  command -v systemctl >/dev/null 2>&1 && systemctl enable --now docker >/dev/null 2>&1
  docker compose version >/dev/null 2>&1 || { err "$(T "Docker Compose v2 not found" "Docker Compose v2 não encontrado")"; return 1; }
  docker info >/dev/null 2>&1 || { err "$(T "Docker daemon is not running: systemctl start docker" "Docker daemon não está rodando: systemctl start docker")"; return 1; }
  ok "$(T "Docker OK (enabled at boot)" "Docker OK (habilitado no boot)")"

  mkdir -p "$APP_DIR"
  local free_gb
  # --output=avail avoids the wrapped-line problem of plain "df" with long device names
  free_gb="$(df -BG --output=avail "$APP_DIR" 2>/dev/null | awk 'NR==2{gsub(/[^0-9]/,"",$1); print $1+0}')"
  if [[ -z "$free_gb" || "$free_gb" == "0" ]]; then
    warn "$(T "could not measure free disk space; continuing" "não foi possível medir o espaço livre; seguindo")"
  elif (( free_gb < 10 )); then
    err "$(T "not enough space in $APP_DIR: ${free_gb}GB free (minimum 10GB)" "espaço insuficiente em $APP_DIR: ${free_gb}GB livres (mínimo 10GB)")"; return 1
  else
    ok "$(T "Disk space: ${free_gb}GB free" "Espaço em disco: ${free_gb}GB livres")"
  fi

  info "$(T "Generating files in $APP_DIR" "Gerando arquivos em $APP_DIR")"
  gerar_arquivos || { err "$(T "failed to generate files" "falha ao gerar arquivos")"; return 1; }
  salvar_idioma

  info "$(T "Configuring the host (swap, limits, .env, cron)..." "Configurando host (swap, limites, .env, cron)...")"
  # Run from a stable cwd: if the shell's current directory was deleted (common
  # when the script is run from a temp/clone path that vanishes), bash prints
  # "getcwd: cannot access parent directories" on every child. Harmless but noisy.
  # Roda a partir de um cwd estável: se o diretório atual do shell foi apagado
  # (comum ao rodar o script de um path temporário/clone que some), o bash
  # imprime "getcwd: cannot access parent directories" em todo filho. Inofensivo, mas barulhento.
  ( cd "$APP_DIR" && bash "$APP_DIR/scripts/setup-host.sh" ) 2>&1 | sed 's/^/    /'
  if [[ "${PIPESTATUS[0]}" -ne 0 ]]; then err "$(T "setup-host failed" "setup-host falhou")"; return 1; fi
  echo
  escolher_tz
  echo
  escolher_wine
  instalar_atalho

  echo
  cd "$APP_DIR" || return 1
  run_spin "$(T "Building the Docker image (5–15 min the first time)" "Construindo imagem Docker (5–15 min na 1ª vez)")" "$APP_DIR/data/logs/host-build.log" \
    timeout 1800 env -u TZ docker compose --progress plain -f "$COMPOSE_FILE" build || return 1
  if ! dc up -d >"$APP_DIR/data/logs/host-up.log" 2>&1; then
    err "$(T "docker compose up failed:" "docker compose up falhou:")"
    tail -n 10 "$APP_DIR/data/logs/host-up.log" | sed 's/^/      /' >&2
    return 1
  fi

  if wait_healthy; then
    printf '\r\033[K'; ok "$(T "Container healthy" "Container saudável")"
  else
    printf '\r\033[K'; warn "$(T "Healthcheck did not become healthy in time. See: mt-menu → 4 (Status)" "Healthcheck não ficou saudável no prazo. Veja: mt-menu → 4 (Status)")"
  fi

  echo
  ok "${C_BOLD}$(T "Base installation finished" "Instalação base concluída")${C_RESET}"
  echo
  # Clear and show only access info so the user can copy without scrolling through logs.
  # Limpa e mostra só o acesso para o usuário copiar sem rolar logs.
  mostrar_acesso_limpo
  echo
  echo "  ${C_BOLD}$(T "Next step:" "Próximo passo:")${C_RESET} $(T "option 2 (install MT4/MT5), then option 3 (bots)." "opção 2 (instalar MT4/MT5), depois opção 3 (robôs).")"
  echo "  ${C_DIM}$(T "Shortcut to come back to this menu: sudo mt-menu" "Atalho para voltar a este menu: sudo mt-menu")${C_RESET}"
}

# -----------------------------------------------------------------------------
# Step 2 — Install MT4 + MT5 / Etapa 2 — Instalar MT4 + MT5
# -----------------------------------------------------------------------------
instalar_terminal() { # instalar_terminal mt4|mt5 [--keep-stopped]
  local id="$1" keep_stopped=0 args=() rc=0 log="$APP_DIR/data/logs/host-install-$1.log"
  shift || true
  [[ "${1:-}" == "--keep-stopped" ]] && keep_stopped=1

  # MT4 with a win32 prefix can't run the 64-bit installer ("Bad EXE format").
  # If MT4 isn't installed yet, migrate to win64 and recreate the prefix.
  if [[ "$id" == "mt4" && ! -s "$APP_DIR/data/prefix-mt4/.mt_exe_path" ]]; then
    local migrou=0
    if [[ "$(env_get MT4_ARCH)" != "win64" ]]; then env_set MT4_ARCH win64; migrou=1; fi
    if grep -qs '^#arch=win32' "$APP_DIR/data/prefix-mt4/system.reg"; then
      warn "$(T "Old MT4 prefix is win32; recreating it as win64..." "Prefixo antigo do MT4 é win32; recriando como win64...")"
      dc exec -T mt mt-sv stop mt4 >/dev/null 2>&1 || true
      find "$APP_DIR/data/prefix-mt4" -mindepth 1 -delete 2>/dev/null
      migrou=1
    fi
    if (( migrou )); then
      dc up -d --force-recreate >/dev/null 2>&1
      wait_supervisor || { err "$(T "container did not come back" "container não voltou")"; return 1; }
    fi
  fi

  if [[ -s "$APP_DIR/data/prefix-$id/.mt_exe_path" ]]; then
    warn "$(T "${id^^} is already installed." "${id^^} já está instalado.")"
    if confirm "$(T "Reinstall (--force)?" "Reinstalar (--force)?")"; then args+=(--force); else return 0; fi
  fi

  # Prefer a local installer from data/installers/ (e.g. a broker's); otherwise the
  # official MetaQuotes download is used (mt4oldsetup.exe for MT4).
  local local_inst="" cand
  for cand in "$APP_DIR/data/installers/${id}setup.exe" \
              "$APP_DIR/data/installers/${id}.exe" \
              "$APP_DIR/data/installers/"*${id}*.exe; do
    [[ -f "$cand" ]] || continue
    # For MT4 skip files that look like MT5-only installers if a better name exists
    local_inst="$cand"
    break
  done
  if [[ -n "$local_inst" ]]; then
    info "$(T "Using local installer: $local_inst" "Usando instalador local: $local_inst")"
    # Path inside the container (volume mount is read-only)
    args+=(--installer "/home/mt/installers/$(basename "$local_inst")")
  fi

  echo
  info "$(T "Installing ${id^^} — takes 10 to 30 min. Watch it through noVNC (SSH tunnel shown just above)." "Instalando ${id^^} — leva de 10 a 30 min. Acompanhe pelo noVNC (túnel SSH mostrado logo acima).")"
  dc exec -T mt mt-sv stop "$id" >/dev/null 2>&1 || true
  sleep 2

  run_spin "$(T "Installing ${id^^}" "Instalando ${id^^}")" "$log" \
    dc exec -T mt mt-install "$id" ${args[@]+"${args[@]}"} || rc=$?

  # If interrupted/failed, kill any orphaned mt-install still holding the lock inside the container
  if (( rc != 0 )); then
    dc exec -T mt bash -c 'f=/tmp/mt-install.running; if [[ -f "$f" ]]; then kill "$(cat "$f")" 2>/dev/null || true; rm -f "$f"; fi' >/dev/null 2>&1 || true
  fi

  # Only start the terminal if installation produced the marker (and caller did not ask to keep stopped)
  if [[ -s "$APP_DIR/data/prefix-$id/.mt_exe_path" ]]; then
    if (( keep_stopped == 0 )); then
      dc exec -T mt mt-sv start "$id" >/dev/null 2>&1 || true
    fi
    if (( rc == 0 )); then
      ok "$(T "${id^^} installed and starting" "${id^^} instalado e iniciando")"
    else
      warn "$(T "${id^^} finished with errors but marker exists; check logs" "${id^^} terminou com erros mas o marcador existe; veja os logs")"
    fi
  else
    err "$(T "${id^^} failed. Detailed log: $APP_DIR/data/logs/setup-$id.log" "${id^^} falhou. Log detalhado: $APP_DIR/data/logs/setup-$id.log")"
  fi
  return "$rc"
}

# Removes a terminal: stops the program, kills the prefix's wineserver and deletes the
# whole prefix (terminal, account, EAs, Wine dependencies). Reinstalling redoes everything.
remover_terminal() { # remover_terminal mt4|mt5
  local id="$1" dir="$APP_DIR/data/prefix-$1"
  if container_running; then
    dc exec -T mt mt-sv stop "$id" >/dev/null 2>&1 || true
    dc exec -T -e WINEPREFIX="/home/mt/prefix/$id" mt wineserver -k >/dev/null 2>&1 || true
    sleep 2
  fi
  find "$dir" -mindepth 1 -delete 2>/dev/null
  if [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
    ok "$(T "${id^^} removed" "${id^^} removido")"
  else
    err "$(T "could not delete everything in $dir" "não consegui apagar tudo em $dir")"
    return 1
  fi
}

desinstalar_terminais() {
  local esc ids=() id existentes=()
  echo
  echo "  ${C_BOLD}$(T "Which terminal to uninstall?" "Qual terminal desinstalar?")${C_RESET}"
  echo "    1) MT4"
  echo "    2) MT5"
  echo "    3) $(T "Both" "Ambos")"
  echo "    0) $(T "Back" "Voltar")"
  read -rp "  $(T "Option" "Opção") [0-3]: " esc || true
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
      info "$(T "${id^^} is already empty/not installed" "${id^^} já está vazio/não instalado")"
    fi
  done
  ((${#existentes[@]} > 0)) || return 0

  echo
  warn "$(T "This will DELETE ${existentes[*]^^}: the terminal, the logged-in account, EAs/indicators and" "Vai APAGAR ${existentes[*]^^}: o terminal, a conta logada, os EAs/indicadores e as")"
  warn "$(T "settings. Files in $ROBOS_DIR and your backups are NOT affected." "configurações. Os arquivos em $ROBOS_DIR e os backups NÃO são afetados.")"
  confirm "$(T "Confirm uninstalling ${existentes[*]^^}?" "Confirmar a desinstalação de ${existentes[*]^^}?")" || { info "$(T "cancelled" "cancelado")"; return 0; }

  for id in "${existentes[@]}"; do remover_terminal "$id"; done
  echo
  info "$(T "To install again, use this same option and choose Install." "Para instalar de novo, use esta mesma opção e escolha Instalar.")"
}

etapa_instalar_terminais() {
  title "$(T "2 · MT4 / MT5 — install or uninstall" "2 · MT4 / MT5 — instalar ou desinstalar")"
  require_root
  need_base || return 1

  # the container runs as uid 1000; wrong ownership in data/ causes a restart loop
  chown -R 1000:1000 "$APP_DIR/data" 2>/dev/null
  chmod 700 "$APP_DIR/data/prefix-mt4" "$APP_DIR/data/prefix-mt5" 2>/dev/null

  local acao
  echo "  ${C_BOLD}$(T "What would you like to do?" "O que deseja fazer?")${C_RESET}"
  echo "    1) $(T "Install MT4 / MT5" "Instalar MT4 / MT5")"
  echo "    2) $(T "Uninstall MT4 / MT5" "Desinstalar MT4 / MT5")"
  echo "    0) $(T "Back" "Voltar")"
  read -rp "  $(T "Option" "Opção") [0-2] (Enter=1): " acao || true
  case "${acao:-1}" in
    1) ;;
    2) desinstalar_terminais; return $? ;;
    *) return 0 ;;
  esac
  echo

  if ! container_running; then
    info "$(T "Container stopped — starting..." "Container parado — iniciando...")"
    dc up -d >/dev/null 2>&1
  fi
  info "$(T "Waiting for internal services..." "Aguardando serviços internos...")"
  wait_supervisor || { err "$(T "supervisord did not respond; check the logs (menu 6)" "supervisord não respondeu; veja os logs (menu 6)")"; return 1; }

  # Show access details BEFORE the long install so the user can open the SSH
  # tunnel and watch noVNC without interrupting the guided flow (or any install).
  # Mostra o acesso ANTES da instalação longa para o usuário abrir o túnel SSH
  # e acompanhar pelo noVNC sem interromper a instalação guiada (ou qualquer instalação).
  clear 2>/dev/null || true
  echo
  info "$(T "Open the SSH tunnel NOW if you want to watch the installer through noVNC. The install continues here; you do not need option 7." "Abra o túnel SSH AGORA se quiser acompanhar o instalador pelo noVNC. A instalação continua aqui; não precisa da opção 7.")"
  echo
  mostrar_acesso
  aguardar_copia "$(T "Copy the tunnel command / password above (mouse select). Ctrl+C here does nothing — ENTER when ready to install." "Copie o comando do túnel / senha acima (selecione com o mouse). Ctrl+C aqui não faz nada — ENTER quando estiver pronto para instalar.")"

  echo
  echo "  ${C_BOLD}$(T "Which terminal to install?" "Qual terminal instalar?")${C_RESET} ${C_DIM}($(T "local installer in data/installers/ preferred; else MetaQuotes" "preferência: instalador local em data/installers/; senão MetaQuotes"))${C_RESET}"
  echo "    1) MT4"
  echo "    2) MT5"
  echo "    3) $(T "Both (MT4 first, then MT5 — MT4 kept stopped during MT5 to save RAM)" "Ambos (MT4 primeiro, depois MT5 — MT4 fica parado durante o MT5 para economizar RAM)")"
  echo "    0) $(T "Back" "Voltar")"
  local escolha
  read -rp "  $(T "Option" "Opção") [0-3]: " escolha || true
  case "${escolha:-}" in
    1) instalar_terminal mt4 ;;
    2) instalar_terminal mt5 ;;
    3)
      # Keep MT4 stopped while installing MT5 to avoid OOM on 1 GB VPS
      instalar_terminal mt4 --keep-stopped
      echo
      info "$(T "MT4 left stopped; waiting 20s then installing MT5..." "MT4 deixado parado; aguardando 20s e instalando MT5...")"
      sleep 20
      instalar_terminal mt5 --keep-stopped
      echo
      info "$(T "Starting both terminals..." "Iniciando ambos os terminais...")"
      dc exec -T mt mt-sv start mt4 >/dev/null 2>&1 || true
      dc exec -T mt mt-sv start mt5 >/dev/null 2>&1 || true
      ok "$(T "MT4 and MT5 started (if installed)" "MT4 e MT5 iniciados (se instalados)")"
      ;;
    0) return 0 ;;
    *) warn "$(T "invalid option" "opção inválida")" ;;
  esac
}

# -----------------------------------------------------------------------------
# Step 3 — Bots / Indicators / Etapa 3 — Robôs / Indicadores
# -----------------------------------------------------------------------------
# The terminal's MQL folder ON THE HOST. Since the terminal runs with /portable, its
# data lives next to terminal.exe — we use the marker's path, not "the first MQL4 that
# find returns" (which could be the AppData folder, ignored in portable mode).
mql_dest() { # mql_dest mt4|mt5 Experts|Indicators|Presets
  local id="$1" kind="$2" host_prefix marker exe_c exe_h dir mql
  host_prefix="$APP_DIR/data/prefix-$id"
  marker="$host_prefix/.mt_exe_path"
  [[ -s "$marker" ]] || return 1
  exe_c="$(<"$marker")"
  exe_c="${exe_c//\\//}"                 # backslashes -> slashes
  exe_c="${exe_c#[A-Za-z]:}"              # drop a leading drive letter (Z:)
  exe_h="${exe_c/#"/home/mt/prefix/$id"/$host_prefix}"
  [[ -f "$exe_h" ]] || return 1
  dir="$(dirname "$exe_h")"
  if [[ "$id" == "mt4" ]]; then mql="MQL4"; else mql="MQL5"; fi
  mkdir -p "$dir/$mql/$kind"
  chown 1000:1000 "$dir/$mql" "$dir/$mql/$kind" 2>/dev/null || true
  printf '%s' "$dir/$mql/$kind"
}

# Folder structure where you drop the files; menu option 3 reads from here.
criar_estrutura_robos() {
  mkdir -p "$ROBOS_DIR"/{MT4,MT5}/{Experts,Indicators} "$ROBOS_DIR/sets" "$BACKUP_DIR" 2>/dev/null || true
  if [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]]; then
    chown -R "$SUDO_USER:" "$ROBOS_DIR" 2>/dev/null || true
    chown "$SUDO_USER:" "$BACKUP_DIR" 2>/dev/null || true
  fi
}

etapa_instalar_robos() {
  title "$(T "3 · Bots, Indicators and Sets" "3 · Robôs, Indicadores e Sets")"
  require_root
  need_base || return 1
  criar_estrutura_robos

  echo "  $(T "Put the files in the right folder, then run this option:" "Coloque os arquivos na pasta certa e depois rode esta opção:")"
  echo
  echo "    ${C_CYAN}$ROBOS_DIR/MT4/Experts${C_RESET}       ${C_DIM}$(T "MT4 bots (.ex4)" "robôs do MT4 (.ex4)")${C_RESET}"
  echo "    ${C_CYAN}$ROBOS_DIR/MT4/Indicators${C_RESET}    ${C_DIM}$(T "MT4 indicators (.ex4)" "indicadores do MT4 (.ex4)")${C_RESET}"
  echo "    ${C_CYAN}$ROBOS_DIR/MT5/Experts${C_RESET}       ${C_DIM}$(T "MT5 bots (.ex5)" "robôs do MT5 (.ex5)")${C_RESET}"
  echo "    ${C_CYAN}$ROBOS_DIR/MT5/Indicators${C_RESET}    ${C_DIM}$(T "MT5 indicators (.ex5)" "indicadores do MT5 (.ex5)")${C_RESET}"
  echo "    ${C_CYAN}$ROBOS_DIR/sets${C_RESET}              ${C_DIM}$(T ".set files (MT4 and MT5 in the same folder)" "arquivos .set (MT4 e MT5 na mesma pasta)")${C_RESET}"
  echo
  echo "  ${C_DIM}$(T "From your PC:" "Do seu PC:") scp -P $SSH_PORT MyBot.ex5 root@$(server_ip):$ROBOS_DIR/MT5/Experts/${C_RESET}"
  echo

  local f
  # warnings: file in the wrong place
  while IFS= read -r -d '' f; do
    warn "$(T "ignored (MT5 extension in the MT4 folder)" "ignorado (extensão do MT5 na pasta do MT4)"): ${f#"$ROBOS_DIR"/}"
  done < <(find "$ROBOS_DIR/MT4" -maxdepth 2 -type f \( -iname '*.ex5' -o -iname '*.mq5' \) -print0 2>/dev/null)
  while IFS= read -r -d '' f; do
    warn "$(T "ignored (MT4 extension in the MT5 folder)" "ignorado (extensão do MT4 na pasta do MT5)"): ${f#"$ROBOS_DIR"/}"
  done < <(find "$ROBOS_DIR/MT5" -maxdepth 2 -type f \( -iname '*.ex4' -o -iname '*.mq4' \) -print0 2>/dev/null)
  while IFS= read -r -d '' f; do
    warn "$(T "loose in the root (move it to MT4/ or MT5/)" "solto na raiz (mova para MT4/ ou MT5/)"): $(basename "$f")"
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
        err "$(T "${id^^}/$kind: ${#files[@]} file(s) waiting, but ${id^^} is not installed (option 2)." "${id^^}/$kind: ${#files[@]} arquivo(s) aguardando, mas o ${id^^} não está instalado (opção 2).")"
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
          err "$(T "failed to copy $base" "falha ao copiar $base")"
        fi
      done
    done
  done

  # ---- Sets (.set): one folder; asks which terminal the first time ----
  # The choice is saved in sets/.destinos; next times it copies without asking.
  local memo="$ROBOS_DIR/sets/.destinos" alvo resp
  local -a sets=()
  while IFS= read -r -d '' f; do sets+=("$f"); done \
    < <(find "$ROBOS_DIR/sets" -maxdepth 1 -type f -iname '*.set' -print0 2>/dev/null | sort -z)
  for f in ${sets[@]+"${sets[@]}"}; do
    base="$(basename "$f")"
    total=$((total + 1))
    alvo=""
    [[ -f "$memo" ]] && alvo="$(awk -F'|' -v n="$base" '$1==n{print $2; exit}' "$memo")"
    if [[ -z "$alvo" ]]; then
      echo
      echo "  ${C_BOLD}$base${C_RESET} ${C_DIM}($(T "new set" "set novo"))${C_RESET}"
      echo "    1) MT4    2) MT5    0) $(T "Leave as is" "Deixar como está")"
      read -rp "    $(T "Which terminal?" "Para qual terminal?") [0-2]: " resp || true
      case "${resp:-0}" in
        1) alvo="mt4" ;;
        2) alvo="mt5" ;;
        *) info "  $(T "left in sets/" "deixado em sets/"): $base"; deixados=$((deixados + 1)); continue ;;
      esac
      novo_set=1
    else
      novo_set=0
    fi
    destino="$(mql_dest "$alvo" Presets || true)"
    if [[ -z "$destino" ]]; then
      err "$(T "$base: ${alvo^^} is not installed yet (option 2)." "$base: ${alvo^^} ainda não está instalado (opção 2).")"
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
      err "$(T "failed to copy $base" "falha ao copiar $base")"
      continue
    fi
    if (( novo_set )); then printf '%s|%s\n' "$base" "$alvo" >> "$memo"; fi
  done

  echo
  if (( total == 0 )); then
    warn "$(T "No files found in the folders above." "Nenhum arquivo encontrado nas pastas acima.")"
    return 0
  fi
  info "$(T "$total file(s) in the folders: $novos new/updated, $iguais already identical, $pendentes pending, $deixados left in sets/." "$total arquivo(s) nas pastas: $novos novo(s)/atualizado(s), $iguais já estavam iguais, $pendentes pendente(s), $deixados deixado(s) em sets/.")"
  if (( novos > 0 )); then
    if container_running && confirm "$(T "Restart MT4/MT5 so the Navigator picks up the new files?" "Reiniciar MT4/MT5 para o Navigator reconhecer os novos arquivos?")"; then
      dc exec -T mt mt-sv restart mt4 >/dev/null 2>&1 || true
      dc exec -T mt mt-sv restart mt5 >/dev/null 2>&1 || true
      ok "$(T "Terminals restarted (the ones that are installed)" "Terminais reiniciados (os que estão instalados)")"
    fi
    echo
    echo "  ${C_DIM}$(T "In MetaTrader: Navigator → Expert Advisors / Indicators (or right click → Refresh)." "No MetaTrader: Navigator → Expert Advisors / Indicators (ou botão direito → Atualizar).")${C_RESET}"
    echo "  ${C_DIM}$(T "Remember to enable \"Algo Trading\" / \"Allow automated trading\" in the terminal." "Lembre de ativar \"Algo Trading\" / \"Permitir negociação automatizada\" no terminal.")${C_RESET}"
  fi
}

# -----------------------------------------------------------------------------
# Step 4 — Status / Diagnostics / Etapa 4 — Status / Diagnóstico
# -----------------------------------------------------------------------------
etapa_status() {
  title "$(T "4 · Status and diagnostics" "4 · Status e diagnóstico")"
  require_root
  need_base || return 1
  local cn; cn="$(container_name)"

  echo "  ${C_BOLD}Container${C_RESET}"; rule 30
  dc ps 2>&1 | sed 's/^/  /' || true
  echo

  if container_running; then
    echo "  ${C_BOLD}$(T "Internal services (supervisord)" "Serviços internos (supervisord)")${C_RESET}"; rule 30
    dc exec -T mt mt-sv status 2>/dev/null | sed 's/^/  /' || warn "$(T "could not query supervisord" "não foi possível consultar o supervisord")"
    echo
    echo "  ${C_BOLD}$(T "Terminal processes" "Processos dos terminais")${C_RESET}"; rule 30
    local procs
    procs="$(dc exec -T mt ps aux 2>/dev/null | grep -E 'terminal(64)?\.exe' | grep -v grep | cut -c1-$((COLS - 2)) | sed 's/^/  /')"
    if [[ -n "$procs" ]]; then echo "$procs"; else echo "  $(T "(no terminal running)" "(nenhum terminal rodando)")"; fi
    echo
    echo "  ${C_BOLD}$(T "Resources" "Recursos")${C_RESET}"; rule 30
    docker stats --no-stream --format '  CPU {{.CPUPerc}}   RAM {{.MemUsage}} ({{.MemPerc}})   PIDs {{.PIDs}}' "$cn" 2>/dev/null || true
    free -m | awk 'NR==1||/Mem|Swap/' | sed 's/^/  /'
    df -h --output=used,size,pcent "$APP_DIR" | awk -v d="$(T "Disk:" "Disco:")" -v u="$(T "used of" "usados de")" 'NR==2{printf "  %s %s %s %s (%s)\n", d, $1, u, $2, $3}'
    echo
    echo "  ${C_BOLD}$(T "Last log lines" "Últimas linhas do log")${C_RESET}"; rule 30
    dc exec -T mt tail -8 /home/mt/logs/mt-docker.log 2>/dev/null | cut -c1-$((COLS - 2)) | sed 's/^/  /' || true
  else
    warn "$(T "Container is not running (menu 5 → Start)." "Container não está rodando (menu 5 → Iniciar).")"
  fi
  echo
  mostrar_acesso
}

# -----------------------------------------------------------------------------
# Step 5 — Operation / Etapa 5 — Operação
# -----------------------------------------------------------------------------
etapa_operacao() {
  need_base || { pause; return; }
  local op rc
  while true; do
    title "$(T "5 · Operation" "5 · Operação")"
    painel; echo
    echo "    1) $(T "Restart the whole container" "Reiniciar o container inteiro")"
    echo "    2) $(T "Stop the container" "Parar o container")"
    echo "    3) $(T "Start the container" "Iniciar o container")"
    echo "    4) $(T "Restart MT4" "Reiniciar MT4")        5) $(T "Restart MT5" "Reiniciar MT5")"
    echo "    6) $(T "Stop MT4" "Parar MT4")           7) $(T "Stop MT5" "Parar MT5")"
    echo "    8) $(T "Start MT4" "Iniciar MT4")          9) $(T "Start MT5" "Iniciar MT5")"
    echo "    0) $(T "Back" "Voltar")"
    echo
    rc=0; ask op "  $(T "Option" "Opção") [0-9]: " || rc=$?
    (( rc == 1 )) && return
    (( rc == 2 )) && continue
    case "$op" in
      1) confirm "$(T "Restart the whole container?" "Reiniciar o container inteiro?")" && { dc restart >/dev/null 2>&1 && ok "$(T "container restarted" "container reiniciado")" || err "$(T "failed" "falhou")"; } ;;
      2) confirm "$(T "Stop the container (the terminals close)?" "Parar o container (os terminais fecham)?")" && { dc stop >/dev/null 2>&1 && ok "$(T "container stopped" "container parado")" || err "$(T "failed" "falhou")"; } ;;
      3) dc up -d >/dev/null 2>&1 && ok "$(T "container started" "container iniciado")" || err "$(T "failed" "falhou")" ;;
      4) dc exec -T mt mt-sv restart mt4 2>&1 | sed 's/^/  /' ;;
      5) dc exec -T mt mt-sv restart mt5 2>&1 | sed 's/^/  /' ;;
      6) dc exec -T mt mt-sv stop mt4 2>&1 | sed 's/^/  /' ;;
      7) dc exec -T mt mt-sv stop mt5 2>&1 | sed 's/^/  /' ;;
      8) dc exec -T mt mt-sv start mt4 2>&1 | sed 's/^/  /' ;;
      9) dc exec -T mt mt-sv start mt5 2>&1 | sed 's/^/  /' ;;
      0) return ;;
      *) warn "$(T "invalid option" "opção inválida")" ;;
    esac
    pause
  done
}

# -----------------------------------------------------------------------------
# Step 6 — Maintenance / Etapa 6 — Manutenção
# -----------------------------------------------------------------------------
fazer_backup() {
  run_spin "$(T "Creating backup" "Gerando backup")" "$APP_DIR/data/logs/host-backup.log" bash "$APP_DIR/scripts/backup.sh" || return 1
  ls -1t "$BACKUP_DIR"/mt-backup-*.tar.gz 2>/dev/null | head -3 | while read -r b; do
    echo "    ${C_DIM}$(du -h "$b" | cut -f1)  $b${C_RESET}"
  done
  echo "  ${C_DIM}$(T "Folder" "Pasta"): $BACKUP_DIR ($(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1) $(T "in total; nothing is deleted automatically" "no total; nada é apagado automaticamente"))${C_RESET}"
}

restaurar_backup() {
  local bks=() b i=1 n listing p
  while IFS= read -r b; do bks+=("$b"); done < <(ls -1t "$BACKUP_DIR"/mt-backup-*.tar.gz 2>/dev/null)
  if ((${#bks[@]} == 0)); then warn "$(T "No backups in $BACKUP_DIR" "Nenhum backup em $BACKUP_DIR")"; return 0; fi
  echo "  ${C_BOLD}$(T "Available backups:" "Backups disponíveis:")${C_RESET}"
  for b in "${bks[@]}"; do
    printf '    %2d) %s  %s(%s)%s\n' "$i" "$(basename "$b")" "$C_DIM" "$(du -h "$b" | cut -f1)" "$C_RESET"
    i=$((i + 1))
  done
  read -rp "  $(T "Restore which one?" "Restaurar qual?") [1-${#bks[@]}, $(T "0=cancel" "0=cancelar")]: " n || true
  if ! [[ "${n:-0}" =~ ^[0-9]+$ ]] || (( n < 1 || n > ${#bks[@]} )); then info "$(T "cancelled" "cancelado")"; return 0; fi
  b="${bks[n-1]}"
  warn "$(T "This REPLACES the current MT4/MT5 data (accounts, EAs, settings) with the backup's content." "Isso SUBSTITUI os dados atuais de MT4/MT5 (contas, EAs, configurações) pelo conteúdo do backup.")"
  confirm "$(T "Confirm restoring $(basename "$b")?" "Confirmar restauração de $(basename "$b")?")" || { info "$(T "cancelled" "cancelado")"; return 0; }

  dc stop >/dev/null 2>&1 || true
  # List the archive ONCE into a variable. (Piping "tar -t | grep -q" with pipefail
  # fails with SIGPIPE on big archives and the old drive_c would not be removed.)
  listing="$(tar -tzf "$b" 2>/dev/null)"
  for p in prefix-mt4 prefix-mt5; do
    if grep -q "^$p/drive_c" <<< "$listing"; then
      rm -rf "$APP_DIR/data/$p/drive_c"
    fi
  done
  if tar -C "$APP_DIR/data" -xzf "$b"; then
    chown -R 1000:1000 "$APP_DIR/data"
    chmod 700 "$APP_DIR/data/prefix-mt4" "$APP_DIR/data/prefix-mt5" 2>/dev/null
    ok "$(T "Backup restored" "Backup restaurado")"
  else
    err "$(T "failed to extract the backup" "falha ao extrair o backup")"
  fi
  dc up -d >/dev/null 2>&1 && ok "$(T "container started" "container iniciado")"
}

trocar_senha_vnc() {
  local pw
  read -rsp "  $(T "New VNC password (min. 8; only the first 8 characters count): " "Nova senha VNC (mín. 8; só os 8 primeiros caracteres valem): ")" pw || true; echo
  if (( ${#pw} < 8 )); then err "$(T "password too short" "senha curta demais")"; return 1; fi
  pw="${pw:0:8}"
  # The value goes into .env, which docker compose parses: keep it to safe characters.
  if [[ ! "$pw" =~ ^[A-Za-z0-9_.@+=-]{8}$ ]]; then
    err "$(T "use only letters, digits and _ . @ + = - (first 8 characters)" "use apenas letras, números e _ . @ + = - (primeiros 8 caracteres)")"
    return 1
  fi
  confirm "$(T "The container will be recreated and MT4/MT5 will restart. Continue?" "O container será recriado e MT4/MT5 vão reiniciar. Continuar?")" || { info "$(T "cancelled" "cancelado")"; return 0; }
  env_set VNC_PASSWORD "$pw"
  info "$(T "Recreating the container to apply it..." "Recriando o container para aplicar...")"
  dc up -d --force-recreate >/dev/null 2>&1 && ok "$(T "Password changed" "Senha alterada")" || err "$(T "failed to recreate" "falhou ao recriar")"
}

desinstalar() {
  warn "$(T "This removes the container and the image. Your data is only deleted if you ask for it." "Isto remove o container e a imagem. Seus dados só serão apagados se você pedir.")"
  confirm "$(T "Continue with the uninstall?" "Continuar com a desinstalação?")" || { info "$(T "cancelled" "cancelado")"; return 0; }
  # --rmi all: the image has a custom name (image: in the compose file), which
  # "--rmi local" would NOT remove.
  dc down --rmi all >/dev/null 2>&1 && ok "$(T "container and image removed" "container e imagem removidos")"
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
  # Always drop compose/Dockerfile so need_base/painel report "base not installed"
  # (otherwise menu option 5→Start fails with "container does not exist").
  rm -f "$COMPOSE_FILE" "$APP_DIR/Dockerfile" "$APP_DIR/.dockerignore" 2>/dev/null || true
  echo
  echo "  $(T "Account data is still in:" "Dados das contas continuam em:") ${C_CYAN}$APP_DIR/data${C_RESET}"
  echo "  $(T "Bots and backups stay in" "Robôs e backups ficam em") ${C_CYAN}$ROBOS_DIR${C_RESET} $(T "and" "e") ${C_CYAN}$BACKUP_DIR${C_RESET} $(T "(not deleted)." "(não são apagados).")"
  echo "  ${C_DIM}$(T "To use them again, run option 1 (base install) — prefixes are reused." "Para usá-los de novo, rode a opção 1 (instalação base) — os prefixos são reaproveitados.")${C_RESET}"
  local t; read -rp "  $(T "To DELETE EVERYTHING type DELETE (Enter keeps it): " "Para APAGAR TUDO digite APAGAR (Enter mantém): ")" t || true
  if [[ "${t:-}" == "APAGAR" || "${t:-}" == "DELETE" ]]; then
    rm -rf "${APP_DIR:?}" && ok "$(T "$APP_DIR deleted" "$APP_DIR apagado")"
  else
    info "$(T "data kept (re-run base install to recreate the container)" "dados mantidos (rode a instalação base de novo para recriar o container)")"
  fi
}

etapa_manutencao() {
  need_base || { pause; return; }
  local op rc
  while true; do
    title "$(T "6 · Maintenance" "6 · Manutenção")"
    echo "    1) $(T "Make a backup now" "Fazer backup agora")"
    echo "    2) $(T "Restore a backup" "Restaurar um backup")"
    echo "    3) $(T "Update (backup + rebuild image)" "Atualizar (backup + reconstruir imagem)")"
    echo "    4) $(T "Live logs (Ctrl+C goes back)" "Ver logs em tempo real (Ctrl+C volta)")"
    echo "    5) $(T "Live resource usage (Ctrl+C goes back)" "Consumo de recursos ao vivo (Ctrl+C volta)")"
    echo "    6) $(T "Change the VNC password" "Trocar senha do VNC")"
    echo "    7) $(T "Change the timezone" "Trocar fuso horário")"
    echo "    8) $(T "Uninstall" "Desinstalar")"
    echo "    0) $(T "Back" "Voltar")"
    echo
    rc=0; ask op "  $(T "Option" "Opção") [0-8]: " || rc=$?
    (( rc == 1 )) && return
    (( rc == 2 )) && continue
    case "$op" in
      1) fazer_backup ;;
      2) restaurar_backup ;;
      3) if confirm "$(T "Make a backup, rebuild the image and restart?" "Fazer backup, reconstruir imagem e reiniciar?")"; then
           run_spin "$(T "Updating" "Atualizando")" "$APP_DIR/data/logs/host-update.log" bash "$APP_DIR/scripts/update.sh"
         fi ;;
      4) dc logs -f --tail 50 mt ;;
      5) docker stats "$(container_name)" ;;
      6) trocar_senha_vnc ;;
      7) escolher_tz && confirm "$(T "Restart the container to apply the new timezone?" "Reiniciar o container para aplicar o novo fuso?")" && dc up -d --force-recreate >/dev/null 2>&1 && ok "$(T "applied" "aplicado")" ;;
      8) desinstalar; [[ -d "$APP_DIR" ]] || return ;;
      0) return ;;
      *) warn "$(T "invalid option" "opção inválida")" ;;
    esac
    pause
  done
}

etapa_acesso() {
  need_base || return 1
  # Clear + only access block so copying is easy; Ctrl+C safe while waiting.
  # Limpa + só o bloco de acesso para facilitar a cópia; Ctrl+C seguro na espera.
  mostrar_acesso_limpo
}

# -----------------------------------------------------------------------------
# Guided install (everything in sequence) / Instalação guiada
# -----------------------------------------------------------------------------
etapa_guiada() {
  title "$(T "A · Guided installation" "A · Instalação guiada")"
  echo "  $(T "I will run, in order:" "Vou executar, em ordem:") ${C_BOLD}$(T "base → MT4/MT5 → bots" "base → MT4/MT5 → robôs")${C_RESET}."
  echo "  $(T "Estimated total time: 30–60 min (most of it is automatic)." "Tempo total estimado: 30–60 min (a maior parte é automática).")"
  echo
  confirm "$(T "Start?" "Começar?")" || return 0
  etapa_instalar_base || { err "$(T "Base failed; stopping." "Base falhou; interrompendo.")"; return 1; }
  echo; read -rp "  $(T "ENTER to continue to MT4/MT5..." "ENTER para seguir ao MT4/MT5...")" _ || true
  etapa_instalar_terminais
  echo; read -rp "  $(T "ENTER to continue to bots/indicators..." "ENTER para seguir aos robôs/indicadores...")" _ || true
  etapa_instalar_robos
  echo
  ok "${C_BOLD}$(T "All done." "Tudo pronto.")${C_RESET} $(T "Use" "Use") ${C_CYAN}sudo mt-menu${C_RESET} $(T "whenever you want to come back." "quando quiser voltar.")"
}

# -----------------------------------------------------------------------------
# Main menu / Menu principal
# -----------------------------------------------------------------------------
run_etapa() {
  "$@"
  pause
}

trocar_idioma() {
  escolher_idioma
  if [[ -f "$COMPOSE_FILE" ]]; then
    info "$(T "The container's own log messages switch language the next time it is recreated." "As mensagens de log do próprio container mudam de idioma na próxima vez que ele for recriado.")"
  fi
}

menu() {
  local opt rc
  while true; do
    clear 2>/dev/null || true
    echo
    echo "  ${C_BOLD}${C_CYAN}$(T "MetaTrader 4 + 5 in Docker · noVNC" "MetaTrader 4 + 5 em Docker · noVNC")${C_RESET}"
    rule
    painel
    rule
    echo "  ${C_DIM}$(T "Bots" "Robôs"): $ROBOS_DIR${C_RESET}"
    echo "  ${C_DIM}Backups: $BACKUP_DIR${C_RESET}"
    echo
    echo "   ${C_BOLD}A)${C_RESET} $(T "Guided installation" "Instalação guiada") ${C_DIM}($(T "recommended the first time" "recomendado na 1ª vez"))${C_RESET}"
    echo
    echo "   ${C_BOLD}1)${C_RESET} $(T "Install base               " "Instalar base              ") ${C_DIM}$(T "Docker, swap, image" "Docker, swap, imagem")${C_RESET}"
    echo "   ${C_BOLD}2)${C_RESET} $(T "Install / remove MT4/5     " "Instalar / remover MT4/5   ") ${C_DIM}$(T "install or uninstall" "instala ou desinstala")${C_RESET}"
    echo "   ${C_BOLD}3)${C_RESET} $(T "Bots, Indicators and Sets  " "Robôs, Indicadores e Sets  ") ${C_DIM}.ex4 .ex5 .set${C_RESET}"
    echo "   ${C_BOLD}4)${C_RESET} $(T "Status and diagnostics" "Status e diagnóstico")"
    echo "   ${C_BOLD}5)${C_RESET} $(T "Operation                  " "Operação                   ") ${C_DIM}$(T "start / stop / restart" "iniciar / parar / reiniciar")${C_RESET}"
    echo "   ${C_BOLD}6)${C_RESET} $(T "Maintenance                " "Manutenção                 ") ${C_DIM}$(T "backup, update, logs, password" "backup, update, logs, senha")${C_RESET}"
    echo "   ${C_BOLD}7)${C_RESET} $(T "How to access              " "Como acessar               ") ${C_DIM}$(T "VNC password and SSH tunnel" "senha VNC e túnel SSH")${C_RESET}"
    echo "   ${C_BOLD}L)${C_RESET} Language / Idioma"
    echo "   ${C_BOLD}0)${C_RESET} $(T "Exit" "Sair")"
    echo
    rc=0; ask opt "  $(T "Choose" "Escolha") [A,L,0-7]: " || rc=$?
    if (( rc == 1 )); then exit 0; fi   # terminal closed / Ctrl+D: leave instead of spinning
    if (( rc == 2 )); then continue; fi # Ctrl+C: just redraw
    case "${opt,,}" in
      a) run_etapa etapa_guiada ;;
      1) run_etapa etapa_instalar_base ;;
      2) run_etapa etapa_instalar_terminais ;;
      3) run_etapa etapa_instalar_robos ;;
      4) run_etapa etapa_status ;;
      5) etapa_operacao ;;
      6) etapa_manutencao ;;
      7) run_etapa etapa_acesso ;;
      l) run_etapa trocar_idioma ;;
      0|q|exit|sair) echo; info "$(T "Goodbye." "Até logo.")"; exit 0 ;;
      "") ;;
      *) warn "$(T "invalid option" "opção inválida")"; sleep 1 ;;
    esac
  done
}

main() {
  local lang_arg="" cmd
  local -a rest=()
  while (($#)); do
    case "$1" in
      --lang)   lang_arg="${2:-}"; shift 2 2>/dev/null || shift ;;
      --lang=*) lang_arg="${1#--lang=}"; shift ;;
      *)        rest+=("$1"); shift ;;
    esac
  done
  cmd="${rest[0]:-menu}"

  init_lang
  if [[ -n "$lang_arg" ]]; then
    norm_lang "$lang_arg" || { LANG_UI="en"; die "invalid language / idioma inválido: '$lang_arg' (en|pt)"; }
  fi

  case "$cmd" in -h|--help|help|ajuda) usage; return 0 ;; esac

  require_root
  if [[ -z "$LANG_UI" ]]; then
    escolher_idioma                    # first run: ask (or guess from the system locale)
  elif [[ -n "$lang_arg" ]]; then
    salvar_idioma                      # explicit --lang: remember it
  fi

  # keeps the "mt-menu" shortcut always on the latest version of this script
  [[ -d "$APP_DIR/scripts" ]] && instalar_atalho
  criar_estrutura_robos
  case "$cmd" in
    menu)                 menu ;;
    guiada|guided)        etapa_guiada ;;
    base)                 etapa_instalar_base ;;
    terminais|terminals)  etapa_instalar_terminais ;;
    robos|bots|eas|ea)    etapa_instalar_robos ;;
    status)               etapa_status ;;
    backup)               need_base && fazer_backup ;;
    idioma|language|lang) escolher_idioma ;;
    *) die "$(T "unknown command: $cmd (use: menu guided base terminals bots status backup language)" "comando desconhecido: $cmd (use: menu guiada base terminais robos status backup idioma)")" ;;
  esac
}

# Allows "source" for tests without running the menu
# Permite "source" para testes sem executar o menu
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
