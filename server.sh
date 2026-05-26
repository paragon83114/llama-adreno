#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

if [ -z "${PREFIX:-}" ]; then
    printf "\033[1;31m✗ Este script requiere Termux.\033[0m\n" >&2
    exit 1
fi

LLAMA_BIN="$HOME/llama-adreno/src/build/bin/llama-server"
MODELO="$HOME/llama-adreno/models/qwen2.5-coder-1.5b-instruct-q8_0.gguf"
LOG_DIR="$HOME/llama-adreno/logs"
LOG_FILE="$LOG_DIR/server-$(date +%Y%m%d-%H%M%S).log"
LOG_LATEST="$LOG_DIR/server-latest.log"

mkdir -p "$LOG_DIR"

if [ ! -f "$LLAMA_BIN" ]; then
    printf "\033[1;31m✗ llama-server no encontrado. Ejecuta: bash ~/llama-adreno/setup.sh\033[0m\n" >&2
    exit 1
fi

if [ ! -f "$MODELO" ]; then
    printf "\033[1;31m✗ Modelo no encontrado: %s\033[0m\n" "$(basename "$MODELO")" >&2
    printf "\n" >&2
    printf "\033[1mDescárgalo con:\033[0m\n" >&2
    printf "  curl -L -o ~/llama-adreno/models/qwen2.5-coder-1.5b-instruct-q8_0.gguf \\\\\n" >&2
    printf '    "https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-1.5b-instruct-q8_0.gguf"\n' >&2
    printf "\n" >&2
    printf "\033[2mO ejecuta: bash ~/llama-adreno/download-model.sh\033[0m\n" >&2
    exit 1
fi

BOLD="\033[1m"
DIM="\033[2m"
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
CYAN="\033[1;36m"
RESET="\033[0m"

printf "\n${CYAN}${BOLD}▗▖▗▗▖▗▖▘▐ ${RESET}${BOLD}llama-server${RESET} ${DIM}for Termux${RESET}\n"
printf "${CYAN}${BOLD}▝▘ ▝ ▝▘▘ ▝▘ ▝▝ ▝▘${RESET}  ${DIM}Qwen2.5-Coder-1.5B · Adreno 830${RESET}\n"
printf "\n"

printf "  ${GREEN}▸${RESET} Endpoint  ${BOLD}http://127.0.0.1:8080/v1${RESET}\n"
printf "  ${GREEN}▸${RESET} Modelo    ${DIM}$(basename "$MODELO")${RESET}\n"
printf "  ${GREEN}▸${RESET} CPU       4 hilos · cores 0-3 · máscara 0xf\n"
printf "  ${GREEN}▸${RESET} GPU       Adreno 830 · -ngl 99\n"
printf "  ${GREEN}▸${RESET} KV Cache  f16 · ctx 32764\n"
printf "  ${GREEN}▸${RESET} Slots     1 (dedicado, sin competencia GPU)\n"
printf "  ${GREEN}▸${RESET} Log       ${DIM}${LOG_LATEST}${RESET}\n"
printf "\n"

apagar() {
    printf "\n\n${YELLOW}⟳${RESET} Apagando servidor (PID %s)...\n" "$SERVER_PID"
    kill "$SERVER_PID" 2>/dev/null || true
    wait "$SERVER_PID" 2>/dev/null || true
    printf "${GREEN}✓${RESET} Servidor detenido\n"

    if [ -L "$LOG_LATEST" ]; then
        local log_size
        log_size=$(wc -c < "$LOG_LATEST" 2>/dev/null || echo "?")
        printf "${DIM}  Log: %s (%s bytes)${RESET}\n" "$(basename "$LOG_LATEST")" "$log_size"
    fi

    exit 0
}

trap apagar SIGINT SIGTERM

printf "${DIM}  Redirigiendo logs de llama-server a archivo...${RESET}\n"
ln -sf "$LOG_FILE" "$LOG_LATEST"

LD_LIBRARY_PATH=/vendor/lib64:$PREFIX/lib:${LD_LIBRARY_PATH:-} "$LLAMA_BIN" \
    --model "$MODELO" \
    --threads 4 \
    --threads-batch 4 \
    -C 0xf --cpu-strict 1 \
    -ngl 99 \
    -ctk f16 -ctv f16 \
    --numa distribute \
    --batch-size 2048 \
    --ubatch-size 512 \
    --ctx-size 32764 \
    --parallel 1 \
    --cont-batching \
    --cache-idle-slots \
    --cache-ram 1024 \
    --kv-unified \
    --timeout 600 \
    --host 127.0.0.1 \
    --port 8080 \
    >> "$LOG_FILE" 2>&1 &

SERVER_PID=$!

printf "${YELLOW}⟳${RESET} Cargando modelo"
for i in {1..60}; do
    if curl -s "http://127.0.0.1:8080/health" > /dev/null 2>&1; then
        printf "\n${GREEN}✓${RESET} Servidor en línea\n"
        break
    fi
    printf "."
    sleep 1
done

if ! curl -s "http://127.0.0.1:8080/health" > /dev/null 2>&1; then
    printf "\n${RED}✗${RESET} El servidor no respondió en 60s. Revisa el log:\n"
    printf "  ${DIM}tail -f %s${RESET}\n" "$LOG_LATEST"
    exit 1
fi

printf "\n${BOLD}Listo.${RESET} Ctrl+C para detener.\n"
printf "${DIM}  Ver log en vivo: tail -f %s${RESET}\n\n" "$LOG_LATEST"

wait "$SERVER_PID"