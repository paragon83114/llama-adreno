#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

BOLD="\033[1m"; GREEN="\033[1;32m"; YELLOW="\033[1;33m"; CYAN="\033[1;36m"; DIM="\033[2m"; RED="\033[1;31m"; RESET="\033[0m"

SYS_PROMPT="You are an expert software engineer. Project context:\n
$(for i in $(seq 1 40); do echo "File $i: src/components/Component$i.tsx - React component with hooks"; done)
\nWhen asked, implement the solution with complete code."

kill_server() {
    fuser -k 8080/tcp 2>/dev/null || true
    sleep 2
}

start_server() {
    local ubatch=$1 batch=$2 ngl=$3
    local logfile="/data/data/com.termux/files/home/llama-adreno/logs/server-cfg-ub${ubatch}-b${batch}-ngl${ngl}.log"
    
    export GGML_OPENCL_ADRENO_XMEM_GEMM=1
    LD_LIBRARY_PATH=/vendor/lib64:$PREFIX/lib \
    /data/data/com.termux/files/home/llama-adreno/src/build/bin/llama-server \
        --model /data/data/com.termux/files/home/llama-adreno/models/qwen2.5-coder-1.5b-instruct-q4_0.gguf \
        --threads 4 --threads-batch 4 -C 0xf --cpu-strict 1 \
        -ngl "$ngl" -ctk f16 -ctv f16 \
        --batch-size "$batch" --ubatch-size "$ubatch" \
        --ctx-size 16384 --parallel 1 --cont-batching \
        --cache-idle-slots --cache-ram 1024 --cache-reuse 256 --kv-unified --keep -1 \
        --poll 20 --timeout 600 --host 127.0.0.1 --port 8080 \
        >> "$logfile" 2>&1 &

    for i in $(seq 1 60); do
        if curl -sf http://127.0.0.1:8080/health > /dev/null 2>&1; then
            return 0
        fi
        sleep 1
    done
    return 1
}

test_cold() {
    local start=$(date +%s%N)
    local resp=$(curl -s --max-time 300 -X POST http://127.0.0.1:8080/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg sys "$SYS_PROMPT" '{
            model: "qwen2.5-coder-1.5b",
            messages: [{role: "system", content: $sys}, {role: "user", content: "Fix the render bug in Component5 - it crashes on empty data array"}],
            max_tokens: 256, temperature: 0.1
        }')")
    local end=$(date +%s%N)
    local elapsed=$(( (end - start) / 1000000 ))
    local pt=$(echo "$resp" | jq -r '.usage.prompt_tokens // 0')
    local ct=$(echo "$resp" | jq -r '.usage.completion_tokens // 0')
    echo "$elapsed $pt $ct"
}

test_warm() {
    local start=$(date +%s%N)
    local resp=$(curl -s --max-time 300 -X POST http://127.0.0.1:8080/v1/chat/completions \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg sys "$SYS_PROMPT" '{
            model: "qwen2.5-coder-1.5b",
            messages: [
                {role: "system", content: $sys},
                {role: "user", content: "Fix the render bug in Component5 - it crashes on empty data array"},
                {role: "assistant", content: "Found the bug. The component needs an empty check before rendering data.items.map()."},
                {role: "user", content: "Great, now also fix Component8 with the same pattern"}
            ],
            max_tokens: 256, temperature: 0.1
        }')")
    local end=$(date +%s%N)
    local elapsed=$(( (end - start) / 1000000 ))
    local pt=$(echo "$resp" | jq -r '.usage.prompt_tokens // 0')
    local ct=$(echo "$resp" | jq -r '.usage.completion_tokens // 0')
    echo "$elapsed $pt $ct"
}

run_test() {
    local ubatch=$1 batch=$2 ngl=$3 label=$4

    printf "\n${CYAN}${BOLD}════════════════════════════════════════════════${RESET}\n"
    printf "${BOLD}  %s${RESET}\n" "$label"
    printf "${DIM}  ubatch=%d batch=%d ngl=%d${RESET}\n" "$ubatch" "$batch" "$ngl"
    printf "${CYAN}${BOLD}════════════════════════════════════════════════${RESET}\n"

    kill_server
    if ! start_server "$ubatch" "$batch" "$ngl"; then
        printf "${RED}✗ Server failed to start${RESET}\n"
        return
    fi
    printf "  ${GREEN}✓${RESET} Server ready\n"

    sleep 2

    # Cold start
    printf "  ${YELLOW}⟳${RESET} Cold start...\n"
    local cold=$(test_cold)
    local cold_t=$(echo "$cold" | awk '{print $1}')
    local cold_pt=$(echo "$cold" | awk '{print $2}')
    local cold_ct=$(echo "$cold" | awk '{print $3}')
    local cold_prefill_tps=$(( cold_pt * 1000 / cold_t ))
    local cold_gen_tps=$(( cold_ct * 1000 / cold_t ))
    printf "    Time: %d ms (%d s) | Tok: %d+%d | Eff: %d t/s prefill, %d t/s gen\n" \
        "$cold_t" "$((cold_t/1000))" "$cold_pt" "$cold_ct" "$cold_prefill_tps" "$cold_gen_tps"

    # Warm (same session, cache should hit)
    printf "  ${YELLOW}⟳${RESET} Warm...\n"
    local warm=$(test_warm)
    local warm_t=$(echo "$warm" | awk '{print $1}')
    local warm_pt=$(echo "$warm" | awk '{print $2}')
    local warm_ct=$(echo "$warm" | awk '{print $3}')
    local warm_prefill_tps=$(( warm_pt * 1000 / warm_t ))
    local warm_gen_tps=$(( warm_ct * 1000 / warm_t ))
    printf "    Time: %d ms (%d s) | Tok: %d+%d | Eff: %d t/s prefill, %d t/s gen\n" \
        "$warm_t" "$((warm_t/1000))" "$warm_pt" "$warm_ct" "$warm_prefill_tps" "$warm_gen_tps"

    # Record
    echo "$label|$ubatch|$batch|$ngl|$cold_t|$cold_pt|$cold_ct|$warm_t|$warm_pt|$warm_ct" >> "$RESULTS"
}

RESULTS="$HOME/llama-adreno/logs/bench-results.txt"
rm -f "$RESULTS"

printf "${BOLD}Benchmark de configuraciones GPU${RESET}\n"
printf "${DIM}Modelo: Qwen2.5-Coder-1.5B Q4_0 | CPU: 4t cores 0-3${RESET}\n\n"

# Baseline: ubatch 1024, batch 2048, ngl 99
run_test 1024 2048 99 "A: Baseline (ub1024 b2048 ngl99)"

# Option A: ubatch 256, batch 512, ngl 99
run_test 256 512 99 "B: ubatch reducido (ub256 b512 ngl99)"

# Option C: ubatch 1024, batch 2048, ngl 20
run_test 1024 2048 20 "C: ngl reducido (ub1024 b2048 ngl20)"

# Option D: ubatch 256, batch 512, ngl 20
run_test 256 512 20 "D: Ambos reducidos (ub256 b512 ngl20)"

printf "\n${CYAN}${BOLD}════════════════════════════════════════════════${RESET}\n"
printf "${BOLD}  Resultados${RESET}\n"
printf "${CYAN}${BOLD}════════════════════════════════════════════════${RESET}\n"
printf "%-30s | %-8s | %-8s | %-8s | %-8s | %-8s\n" "Config" "Cold(ms)" "pt" "ct" "Warm(ms)" "pt"
printf "%s\n" "--------------------------------|---------|---------|---------|---------|--------"
cat "$RESULTS" | while IFS='|' read -r label ub batch ngl cold_t cold_pt cold_ct warm_t warm_pt warm_ct; do
    printf "%-30s | %-8d | %-7d | %-7d | %-8d | %-7d\n" "$label" "$cold_t" "$cold_pt" "$cold_ct" "$warm_t" "$warm_pt"
done

rm -f "$RESULTS"
printf "\n${DIM}Done${RESET}\n"
