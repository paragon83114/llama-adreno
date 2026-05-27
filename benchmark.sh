#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

if [ -z "${PREFIX:-}" ]; then
    printf "\033[1;31m✗ This script requires Termux.\033[0m\n" >&2
    exit 1
fi

BENCH_BIN="$HOME/llama-adreno/src/build/bin/llama-bench"
MODEL="$HOME/llama-adreno/models/qwen2.5-coder-1.5b-instruct-q8_0.gguf"
LOG_DIR="$HOME/llama-adreno/logs"
LOG_FILE="$LOG_DIR/benchmark-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "$LOG_DIR"

if [ ! -f "$BENCH_BIN" ]; then
    printf "\033[1;31m✗ llama-bench not found. Run: bash ~/llama-adreno/setup.sh\033[0m\n" >&2
    exit 1
fi

if [ ! -f "$MODEL" ]; then
    printf "\033[1;31m✗ Model not found: %s\033[0m\n" "$(basename "$MODEL")" >&2
    exit 1
fi

BOLD="\033[1m"
DIM="\033[2m"
GREEN="\033[1;32m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
RESET="\033[0m"

printf "\n${CYAN}${BOLD}■ llama-benchmark${RESET} ${DIM}· Adreno 830 GPU${RESET}\n"
printf "\n"
printf "  Model    ${DIM}%s${RESET}\n" "$(basename "$MODEL")"
printf "  GPU      Adreno 830 (-ngl 99)\n"
printf "  CPU      4 threads · cores 0-3\n"
printf "  KV       f16\n"
printf "  Output   ${DIM}%s${RESET}\n" "$LOG_FILE"
printf "\n"

printf "${YELLOW}⟳${RESET} Running prompt processing (pp) and text generation (tg) benchmarks...\n\n"

LD_LIBRARY_PATH=/vendor/lib64:$PREFIX/lib:${LD_LIBRARY_PATH:-} "$BENCH_BIN" \
    -m "$MODEL" \
    -p 512,1280,2048 \
    -n 128,256 \
    -ngl 99 \
    -t 4 \
    -C 0xf \
    --cpu-strict 1 \
    -ctk f16 -ctv f16 \
    -b 2048 \
    -ub 512 \
    --numa distribute \
    -r 3 \
    -o md \
    2>&1 | tee "$LOG_FILE"

printf "\n${GREEN}✓${RESET} Benchmark complete. Results saved to ${DIM}%s${RESET}\n" "$LOG_FILE"