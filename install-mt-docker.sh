#!/usr/bin/env bash
# =============================================================================
# install-mt-docker.sh — Installer & Manager for MT4/MT5 in Docker with noVNC
# =============================================================================
# Interactive management menu optimized for low-spec VPS (1-2 GB RAM)
#
# Usage:
#   sudo bash install-mt-docker.sh
# =============================================================================
set -euo pipefail

# -----------------------------------------------------------------------------
# Global Configuration
# -----------------------------------------------------------------------------
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${APP_DIR:-/opt/mt-docker}"
SSH_PORT="${SSH_PORT:-22}"
ZIP_URL="${ZIP_URL:-https://drive.usercontent.google.com/download?id=1woBclFYJ85gl85b1ugPwIrXuOsiG2lhW&export=download&confirm=t}"
ZIP_PASSWORD="${ZIP_PASSWORD:-123456}"
INSTALADOR_MT4="gomarketsmu4setup.exe"
INSTALADOR_MT5="gomarketsmu5setup.exe"
COMPOSE_FILE="$APP_DIR/docker-compose.yml"

# Colors
if [[ -t 1 ]]; then
  C_RED=$'\033[0;31m'; C_GREEN=$'\033[0;32m'; C_YELLOW=$'\033[1;33m'
  C_BLUE=$'\033[0;34m'; C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
  C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_BOLD=""; C_RESET=""
fi

# -----------------------------------------------------------------------------
# Utilities
# -----------------------------------------------------------------------------
log()  { echo "$(date '+%Y-%m-%dT%H:%M:%S%z') [$1] ${*:2}" >&2; }
die()  { log ERROR "$*"; exit 1; }
info() { echo "${C_BLUE}ℹ${C_RESET}  $*"; }
ok()   { echo "${C_GREEN}✓${C_RESET}  $*"; }
warn() { echo "${C_YELLOW}⚠${C_RESET}  $*"; }
err()  { echo "${C_RED}✗${C_RESET}  $*" >&2; }

require_root() {
  [[ $EUID -eq 0 ]] || die "Run as root: sudo bash $0"
}

pause() {
  echo
  read -rp "Pressione ENTER para voltar ao menu..." _ || true
}

confirm() {
  local msg="$1" ans
  read -rp "$msg [s/N] " ans || true
  [[ "${ans,,}" == "s" || "${ans,,}" == "y" ]]
}

container_name() {
  local n="mt"
  if [[ -f "$APP_DIR/.env" ]]; then
    n="$(grep -E '^CONTAINER_NAME=' "$APP_DIR/.env" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"' || true)"
    [[ -n "$n" ]] || n="mt"
  fi
  printf '%s' "$n"
}

dc() {
  docker compose -f "$COMPOSE_FILE" "$@"
}

container_running() {
  [[ -f "$COMPOSE_FILE" ]] || return 1
  dc ps -q --status running 2>/dev/null | grep -q .
}

# -----------------------------------------------------------------------------
# Step 1 — Base Installation
# -----------------------------------------------------------------------------
etapa_instalar_base() {
  clear
  echo "${C_BOLD}=== Instalação base ===${C_RESET}"
  echo

  require_root

  if ! command -v docker >/dev/null 2>&1; then
    info "Docker não encontrado. A instalar via get.docker.com..."
    curl -fsSL https://get.docker.com | DEBIAN_FRONTEND=noninteractive sh
  fi
  docker compose version >/dev/null 2>&1 || die "Docker Compose v2 não encontrado"
  docker info >/dev/null 2>&1 || die "Docker daemon inativo. Inicie com: systemctl start docker"
  ok "Docker OK"

  info "A preparar diretório da aplicação em $APP_DIR"
  mkdir -p "$APP_DIR"/{docker/bin,docker/lib,scripts,data/{prefix-mt4,prefix-mt5,logs,installers},backups}

  FREE_GB="$(df -BG "$APP_DIR" 2>/dev/null | awk 'NR==2{gsub(/G/,"",$4); print $4+0}')"
  if [[ -z "$FREE_GB" || "$FREE_GB" == "0" ]]; then
    warn "Não foi possível validar espaço livre em disco; prosseguindo"
  else
    (( FREE_GB >= 10 )) || die "Espaço insuficiente em $APP_DIR: ${FREE_GB}GB livres (mínimo 10GB)"
    ok "Espaço em disco: ${FREE_GB}GB livres"
  fi

  info "A sincronizar ficheiros da estrutura do repositório..."
  cp -f "$REPO_DIR"/Dockerfile "$APP_DIR"/
  cp -f "$REPO_DIR"/docker-compose.yml "$APP_DIR"/
  cp -f "$REPO_DIR"/.dockerignore "$APP_DIR"/
  cp -rf "$REPO_DIR"/docker/* "$APP_DIR"/docker/
  cp -rf "$REPO_DIR"/scripts/* "$APP_DIR"/scripts/

  chmod 755 "$APP_DIR"/docker/bin/* "$APP_DIR"/scripts/*.sh
  chmod 644 "$APP_DIR"/docker/lib/common.sh "$APP_DIR"/docker/supervisord.conf \
            "$APP_DIR"/Dockerfile "$APP_DIR"/docker-compose.yml "$APP_DIR"/.dockerignore

  info "A executar otimizações de sistema e limites de hardware (setup-host)..."
  bash "$APP_DIR/scripts/setup-host.sh"

  local VNC_PW=""
  if [[ -f "$APP_DIR/.env" ]]; then
    VNC_PW="$(grep -E '^VNC_PASSWORD=' "$APP_DIR/.env" | head -1 | cut -d= -f2-)"
  fi

  local CN
  CN="$(container_name)"

  info "A compilar imagem Docker (5–15 min na primeira execução)..."
  cd "$APP_DIR"
  timeout 1800 docker compose build --progress plain || die "Build falhou ou excedeu o limite de 30 minutos"
  docker compose up -d

  info "A aguardar verificação de integridade (healthcheck)..."
  local healthy=0
  for i in $(seq 1 36); do
    st="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$CN" 2>/dev/null || echo missing)"
    if [[ "$st" == "healthy" ]]; then
      healthy=1
      break
    fi
    sleep 5
  done
  docker compose ps

  if (( healthy )); then
    ok "Contentor healthy e operacional"
  else
    warn "Contentor não reportou status healthy no prazo (status atual: ${st:-unknown})"
    warn "Verifique os logs: docker compose -f $COMPOSE_FILE logs --tail 50"
  fi

  echo
  ok "Instalação base concluída com sucesso!"
  echo
  echo "${C_BOLD}=== Informações de Acesso ===${C_RESET}"
  echo "  Diretório:    $APP_DIR"
  echo "  Contentor:    $CN"
  echo "  Senha VNC:    ${C_YELLOW}$VNC_PW${C_RESET}"
  echo "  Porta SSH:    $SSH_PORT"
  echo "  Túnel SSH:    ssh -N -p $SSH_PORT -L 6080:127.0.0.1:6080 root@IP_DA_VPS"
  echo "  noVNC:        http://localhost:6080/vnc.html?autoconnect=1&resize=scale"
  echo
  echo "${C_BOLD}Próximo passo:${C_RESET} utilize a opção 2 do menu para instalar os terminais MT4/MT5"
  pause
}

# -----------------------------------------------------------------------------
# Step 2 — Install Terminals
# -----------------------------------------------------------------------------
etapa_instalar_terminais() {
  clear
  echo "${C_BOLD}=== Instalação de MT4 + MT5 ===${C_RESET}"
  echo

  require_root

  if [[ ! -f "$COMPOSE_FILE" ]]; then
    err "Base não instalada. Execute a opção 1 primeiro."
    pause; return
  fi
  if ! container_running; then
    warn "Contentor inativo. A iniciar serviço..."
    dc up -d
    sleep 15
  fi

  local precisa_baixar=0
  for ARQ in "$INSTALADOR_MT4" "$INSTALADOR_MT5"; do
    [[ -s "$APP_DIR/data/installers/$ARQ" ]] || precisa_baixar=1
  done

  if (( precisa_baixar )); then
    info "A descarregar instaladores..."
    if ! bash "$APP_DIR/scripts/download-installers.sh"; then
      err "Falha no download dos instaladores."
      pause; return
    fi
    ok "Instaladores disponíveis e verificados"
  else
    ok "Instaladores já presentes em $APP_DIR/data/installers/"
  fi

  echo
  echo "Escolha o terminal a instalar:"
  echo "  1) MT4"
  echo "  2) MT5"
  echo "  3) Ambos (MT4 seguido de MT5)"
  echo "  0) Voltar"
  echo
  read -rp "Opção [0-3]: " escolha

  case "$escolha" in
    1) instalar_terminal mt4 ;;
    2) instalar_terminal mt5 ;;
    3)
      info "A iniciar instalação do MT4..."
      instalar_terminal mt4
      echo
      info "A aguardar 30 segundos para estabilização de memória..."
      sleep 30
      instalar_terminal mt5
      ;;
    0) return ;;
    *) warn "Opção inválida" ;;
  esac
  pause
}

instalar_terminal() {
  local id="$1"
  local nome_instalador
  case "$id" in
    mt4) nome_instalador="$INSTALADOR_MT4" ;;
    mt5) nome_instalador="$INSTALADOR_MT5" ;;
    *) err "Terminal inválido: $id"; return 1 ;;
  esac

  local caminho="/home/mt/installers/$nome_instalador"

  echo
  info "A instalar $id..."
  info "Acompanhe visualmente via noVNC: http://localhost:6080/vnc.html?autoconnect=1&resize=scale"
  echo

  dc exec -T mt mt-sv stop "$id" 2>/dev/null || true
  sleep 2

  dc exec -T mt mt-install "$id" --installer "$caminho"
  local rc=$?

  if (( rc == 0 )); then
    ok "$id instalado com sucesso"
    sleep 15
    dc exec -T mt mt-sv status || true
  else
    err "Instalação do $id falhou (rc=$rc). Consulte o registo em: $APP_DIR/data/logs/setup-$id.log"
  fi
}

# -----------------------------------------------------------------------------
# Step 3 — Status & Diagnostics
# -----------------------------------------------------------------------------
etapa_status() {
  clear
  echo "${C_BOLD}=== Estado / Diagnóstico ===${C_RESET}"
  echo

  require_root

  if [[ ! -f "$COMPOSE_FILE" ]]; then
    err "Base não instalada. Execute a opção 1 primeiro."
    pause; return
  fi

  local CN
  CN="$(container_name)"

  echo "${C_BOLD}Contentor Docker:${C_RESET}"
  dc ps || true
  echo

  if container_running; then
    echo "${C_BOLD}Processos de Supervisão Interna:${C_RESET}"
    dc exec -T mt mt-sv status 2>/dev/null || warn "Supervisor inacessível"
    echo

    echo "${C_BOLD}Processos do MetaTrader em Execução:${C_RESET}"
    dc exec -T mt ps aux 2>/dev/null | grep -E 'terminal(64)?\.exe' | grep -v grep \
      || echo "  (nenhum terminal ativo no momento)"
    echo

    echo "${C_BOLD}Utilização de Recursos:${C_RESET}"
    docker stats --no-stream "$CN" || true
    echo

    echo "${C_BOLD}Últimas linhas do registo (log):${C_RESET}"
    dc exec -T mt tail -10 /home/mt/logs/mt-docker.log 2>/dev/null || true
  else
    warn "Contentor inativo."
  fi

  echo
  echo "${C_BOLD}Parâmetros de Ligação:${C_RESET}"
  local VNC_PW=""
  [[ -f "$APP_DIR/.env" ]] && VNC_PW="$(grep -E '^VNC_PASSWORD=' "$APP_DIR/.env" | head -1 | cut -d= -f2-)"
  echo "  Contentor:  $CN"
  echo "  Senha VNC:  ${C_YELLOW}${VNC_PW:-'(consulte o ficheiro .env)'}${C_RESET}"
  echo "  Porta SSH:  $SSH_PORT"
  echo "  Túnel SSH:  ssh -N -p $SSH_PORT -L 6080:127.0.0.1:6080 root@IP_DA_VPS"
  echo "  noVNC:      http://localhost:6080/vnc.html?autoconnect=1&resize=scale"

  pause
}

# -----------------------------------------------------------------------------
# Step 4 — Operations
# -----------------------------------------------------------------------------
etapa_operacao() {
  clear
  echo "${C_BOLD}=== Operações de Controlo ===${C_RESET}"
  echo
  echo "  1) Reiniciar contentor completo"
  echo "  2) Parar contentor"
  echo "  3) Iniciar contentor"
  echo "  4) Reiniciar processo MT4"
  echo "  5) Reiniciar processo MT5"
  echo "  6) Parar processo MT4"
  echo "  7) Parar processo MT5"
  echo "  0) Voltar"
  echo
  read -rp "Opção [0-7]: " op

  case "$op" in
    1)
      if confirm "Reiniciar o contentor completo?"; then
        dc restart && ok "Contentor reiniciado"
      else
        info "Operação cancelada"
      fi
      ;;
    2)
      if confirm "Parar o contentor?"; then
        dc stop && ok "Contentor parado"
      else
        info "Operação cancelada"
      fi
      ;;
    3) dc start && ok "Contentor iniciado" ;;
    4) dc exec -T mt mt-sv restart mt4 && ok "MT4 reiniciado" ;;
    5) dc exec -T mt mt-sv restart mt5 && ok "MT5 reiniciado" ;;
    6) dc exec -T mt mt-sv stop mt4 && ok "MT4 parado" ;;
    7) dc exec -T mt mt-sv stop mt5 && ok "MT5 parado" ;;
    0) return ;;
    *) warn "Opção inválida" ;;
  esac
  pause
}

# -----------------------------------------------------------------------------
# Step 5 — Maintenance
# -----------------------------------------------------------------------------
etapa_manutencao() {
  clear
  echo "${C_BOLD}=== Manutenção do Sistema ===${C_RESET}"
  echo
  echo "  1) Executar cópia de segurança (backup)"
  echo "  2) Reconstruir imagem com atualizações (update)"
  echo "  3) Acompanhar registos em tempo real (Ctrl+C para sair)"
  echo "  4) Monitorizar consumo de recursos ao vivo"
  echo "  0) Voltar"
  echo
  read -rp "Opção [0-4]: " op

  local CN
  CN="$(container_name)"

  case "$op" in
    1) bash "$APP_DIR/scripts/backup.sh" && ok "Backup concluído" ;;
    2)
      if confirm "Reconstruir imagem e reiniciar?"; then
        bash "$APP_DIR/scripts/update.sh" && ok "Atualização concluída"
      else
        info "Operação cancelada"
      fi
      ;;
    3) dc logs -f mt ;;
    4) docker stats "$CN" ;;
    0) return ;;
    *) warn "Opção inválida" ;;
  esac
  pause
}

# -----------------------------------------------------------------------------
# Main Menu Loop
# -----------------------------------------------------------------------------
menu() {
  while true; do
    clear
    echo "${C_BOLD}╔══════════════════════════════════════════════════════════╗${C_RESET}"
    echo "${C_BOLD}║     MT4 + MT5 em Docker com noVNC — Painel de Gestão     ║${C_RESET}"
    echo "${C_BOLD}╚══════════════════════════════════════════════════════════╝${C_RESET}"
    echo
    echo "  ${C_BOLD}1)${C_RESET} Instalação base         ${C_BLUE}(Docker, swap, permissões, build)${C_RESET}"
    echo "  ${C_BOLD}2)${C_RESET} Instalar MT4 + MT5      ${C_BLUE}(download e configuração)${C_RESET}"
    echo "  ${C_BOLD}3)${C_RESET} Estado / Diagnóstico    ${C_BLUE}(processos, logs e consumo)${C_RESET}"
    echo "  ${C_BOLD}4)${C_RESET} Operações de Controlo   ${C_BLUE}(iniciar, parar, reiniciar)${C_RESET}"
    echo "  ${C_BOLD}5)${C_RESET} Manutenção              ${C_BLUE}(backup, atualizações, logs)${C_RESET}"
    echo "  ${C_BOLD}0)${C_RESET} Sair"
    echo
    read -rp "Selecione uma opção [0-5]: " opt

    case "$opt" in
      1) etapa_instalar_base ;;
      2) etapa_instalar_terminais ;;
      3) etapa_status ;;
      4) etapa_operacao ;;
      5) etapa_manutencao ;;
      0) echo; info "Sessão terminada."; exit 0 ;;
      *) warn "Opção inválida"; sleep 1 ;;
    esac
  done
}

main() {
  require_root
  menu
}

main "$@"
