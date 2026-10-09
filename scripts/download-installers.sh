#!/usr/bin/env bash
# =============================================================================
# Download and Extract MetaTrader Installers
# =============================================================================
set -euo pipefail

APP_DIR="${APP_DIR:-/opt/mt-docker}"
DIR="$APP_DIR/data/installers"
ZIP_NAME="mt_comprimido.zip"
ZIP="$DIR/$ZIP_NAME"
URL="${ZIP_URL:-https://drive.usercontent.google.com/download?id=1woBclFYJ85gl85b1ugPwIrXuOsiG2lhW&export=download&confirm=t}"
SENHA="${ZIP_PASSWORD:-123456}"
INSTALADOR_MT4="gomarketsmu4setup.exe"
INSTALADOR_MT5="gomarketsmu5setup.exe"
ARQUIVOS=("$INSTALADOR_MT4" "$INSTALADOR_MT5")

log() { echo "$(date '+%Y-%m-%dT%H:%M:%S%z') [$1] ${*:2}"; }
die() { log ERROR "$*"; exit 1; }

[[ $EUID -eq 0 ]] || die "Root privileges required: sudo bash $0"

mkdir -p "$DIR"
cd "$DIR"

# Ensure extraction dependencies are present
export DEBIAN_FRONTEND=noninteractive
if ! command -v 7z >/dev/null || ! command -v curl >/dev/null || ! command -v file >/dev/null; then
  log INFO "Installing missing utilities: p7zip-full, curl, file"
  apt-get update -qq
  apt-get install -y -qq p7zip-full curl file
fi

# Download archive payload
log INFO "Downloading archive payload: $ZIP_NAME"
rm -f "$ZIP"
curl -fLsS --retry 3 --retry-delay 5 --user-agent "Mozilla/5.0" "$URL" -o "$ZIP"
[[ -s "$ZIP" ]] || die "Download payload verification failed (empty response)"
log INFO "Payload retrieved: $(( $(stat -c %s "$ZIP") / 1024 )) KB"

# Validate MIME archive format
file "$ZIP" | grep -q "Zip archive" || {
  log ERROR "Invalid archive header detected (received HTML instead of ZIP)"
  exit 1
}

# Verify integrity and decrypt password
log INFO "Verifying archive integrity and payload password..."
7z t "-p$SENHA" -bso0 -bsp0 "$ZIP" >/dev/null || die "Corrupt archive or incorrect decryption password"

# Extract installer executables
log INFO "Extracting binaries into $DIR..."
7z x "-p$SENHA" -y -bso0 -bsp0 "$ZIP" "-o$DIR" >/dev/null

# Verify extracted executables
for ARQ in "${ARQUIVOS[@]}"; do
  test -s "$DIR/$ARQ" || die "Missing extracted installer binary: $ARQ"
  file "$DIR/$ARQ" | grep -qE "PE32" || die "$ARQ is not a valid Windows PE executable"
  log INFO "$ARQ — $(du -h "$DIR/$ARQ" | cut -f1) — $(file -b "$DIR/$ARQ")"
done

rm -f "$ZIP"
log INFO "Extraction completed: installer binaries ready in $DIR"
