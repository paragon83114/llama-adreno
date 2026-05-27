#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

if [ -z "${PREFIX:-}" ]; then
    printf "\033[1;31m✗ Este script requiere Termux.\033[0m\n" >&2
    exit 1
fi

LLAMA_BIN="$HOME/llama-adreno/src/build/bin/llama-cli"
MODELO="$HOME/llama-adreno/models/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf"

if [ ! -f "$LLAMA_BIN" ]; then
    printf "\033[1;31m✗ llama-cli no encontrado. Ejecuta: bash ~/llama-adreno/setup.sh\033[0m\n" >&2
    exit 1
fi

if [ ! -f "$MODELO" ]; then
    printf "\033[1;31m✗ Modelo no encontrado: %s\033[0m\n" "$(basename "$MODELO")" >&2
    printf "\n" >&2
    printf "\033[1mDescárgalo con:\033[0m\n" >&2
    printf "  curl -L -o ~/llama-adreno/models/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf \\\\\n" >&2
    printf '    "https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-1.5b-instruct-q4_k_m.gguf"\n' >&2
    printf "\n" >&2
    printf "\033[2mO ejecuta: bash ~/llama-adreno/download-model.sh\033[0m\n" >&2
    exit 1
fi

BOLD="\033[1m"
DIM="\033[2m"
GREEN="\033[1;32m"
CYAN="\033[1;36m"
RESET="\033[0m"

printf "\n${CYAN}${BOLD}▗▖▗▖▗▖▖▗▖▗▗▖▗▖${RESET}\n"
printf "${CYAN}${BOLD}▗▖▘▐ ▘▐ ▐ ▘▐ ▗▗▖${RESET}  ${BOLD}llama-cli${RESET} ${DIM}for Termux${RESET}\n"
printf "${CYAN}${BOLD}▝▘ ▝ ▝▘▘ ▝▘ ▝▝ ▝▘${RESET}  ${DIM}Qwen2.5-Coder-1.5B · Adreno 830${RESET}\n"
printf "\n"
printf "  ${GREEN}▸${RESET} Modelo    ${DIM}$(basename "$MODELO")${RESET}\n"
printf "  ${GREEN}▸${RESET} CPU       4 hilos · cores 0-3 · máscara 0xf\n"
printf "  ${GREEN}▸${RESET} GPU       Adreno 830 · -ngl 99\n"
printf "  ${GREEN}▸${RESET} KV Cache  f16 · ctx 16384\n"
printf "\n"
printf "Escribe tu mensaje. Ctrl+C para salir.\n\n"

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
    --ctx-size 16384 \
    --poll 100 \
    --temp 0.7 \
    --top-p 0.9 \
    --repeat-penalty 1.1 \
    --keep -1 \
    --conversation \
    --color on \
    --no-display-prompt