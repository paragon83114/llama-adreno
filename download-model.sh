#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

MODELO_URL="https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-1.5b-instruct-q4_0.gguf"
MODELO_DIR="$HOME/llama-adreno/models"
MODELO_FILE="$MODELO_DIR/qwen2.5-coder-1.5b-instruct-q4_0.gguf"
MODELO_SIZE="1.0GiB"

BOLD="\033[1m"
DIM="\033[2m"
GREEN="\033[1;32m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
RESET="\033[0m"

if [ -f "$MODELO_FILE" ]; then
    printf "\n${GREEN}✓${RESET} Modelo ya descargado: ${DIM}%s${RESET}\n" "$MODELO_FILE"
    exit 0
fi

printf "\n${CYAN}${BOLD}▗▖▗▖▗▖▖▗▖▗▗▖▗▖${RESET}\n"
printf "${CYAN}${BOLD}▗▖▘▐ ▘▐ ▐ ▘▐ ▗▗▖${RESET}  ${BOLD}Descarga de modelo${RESET}\n"
printf "${CYAN}${BOLD}▝▘ ▝ ▝▘▘ ▝▘ ▝▝ ▝▘${RESET}\n"
printf "\n"
printf "  Modelo:  Qwen2.5-Coder-1.5B-Instruct Q4_0\n"
printf "  Tamaño:  ~%s\n" "$MODELO_SIZE"
printf "  Destino: ${DIM}%s${RESET}\n\n" "$MODELO_FILE"

mkdir -p "$MODELO_DIR"

printf "${YELLOW}⟳${RESET} Descargando...\n"
curl -L -# -o "$MODELO_FILE" "$MODELO_URL"

if [ -f "$MODELO_FILE" ]; then
    printf "\n${GREEN}✓${RESET} Descarga completa: ${DIM}%s${RESET}\n" "$MODELO_FILE"
    printf "\nAhora puedes iniciar el servidor con: ${BOLD}bash ~/llama-adreno/server.sh${RESET}\n\n"
else
    printf "\n${RED}✗ La descarga falló. Reintenta con:${RESET}\n"
    printf "  curl -L -o %s \\\\\n" "$MODELO_FILE"
    printf '    "%s"\n\n' "$MODELO_URL"
    exit 1
fi