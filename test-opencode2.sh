#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ENDPOINT="http://127.0.0.1:8080/v1/chat/completions"
SYS_PROMPT="You are an expert software engineer. You have access to the following project files and context:

$(for i in $(seq 1 40); do echo "File $i: src/components/Component$i.tsx - React component with hooks"; done)

When asked to make changes, read the relevant file first, then implement the solution."

BOLD="\033[1m"; GREEN="\033[1;32m"; CYAN="\033[1;36m"; DIM="\033[2m"; RESET="\033[0m"

send() {
    local name="$1" msg="$2" max_tok="$3" label="$4"
    printf "\n${CYAN}${BOLD}━━━ %s ━━━${RESET}\n" "$name"
    printf "  ${DIM}%s${RESET}\n" "$label"

    local start=$(date +%s%N)
    local resp=$(curl -s --max-time 600 -X POST "$ENDPOINT" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg sys "$SYS_PROMPT" --arg msg "$msg" --argjson mt "$max_tok" '{
            model: "qwen2.5-coder-1.5b",
            messages: [{role: "system", content: $sys}, {role: "user", content: $msg}],
            max_tokens: $mt,
            temperature: 0.1
        }')")
    local end=$(date +%s%N)
    local elapsed=$(( (end - start) / 1000000 ))

    local err=$(echo "$resp" | jq -r '.error.message // empty')
    if [ -n "$err" ]; then printf "  ⚠ Error: %s\n" "$err"; return; fi

    local pt=$(echo "$resp" | jq -r '.usage.prompt_tokens // 0')
    local ct=$(echo "$resp" | jq -r '.usage.completion_tokens // 0')
    local txt=$(echo "$resp" | jq -r '.choices[0].message.content // ""' | head -c 80 | tr '\n' ' ')

    printf "  ▸ Tiempo:  ${BOLD}%d ms${RESET} (%d s)\n" "$elapsed" "$((elapsed / 1000))"
    printf "  ▸ Tokens:  %d prompt + %d completion\n" "$pt" "$ct"
    if [ "$elapsed" -gt 0 ] && [ "$pt" -gt 0 ]; then printf "  ▸ Prefill: ${BOLD}~%d t/s${RESET}\n" "$(( pt * 1000 / elapsed ))"; fi
    if [ "$elapsed" -gt 0 ] && [ "$ct" -gt 0 ]; then printf "  ▸ Gen:     ${BOLD}~%d t/s${RESET}\n" "$(( ct * 1000 / elapsed ))"; fi
    printf "  ${DIM}→ %s${RESET}\n" "$txt"
}

printf "${CYAN}${BOLD}══════════════════ opencode test ══════════════════${RESET}\n"

send "1. Cold Start" \
    "Review Component5 and fix the render bug" \
    256 \
    "~4000 tok system prompt + user msg, 256 tok gen"

send "2. Warm (same)" \
    "Review Component5 and fix the render bug" \
    256 \
    "Mismo prompt -> cache hit"

send "3. Tool call round-trip" \
    $'I read Component5.tsx:\n\nimport React from \'react\';\nexport const Component5 = ({ data }) => (\n  <div>{data.items.map(i => <span>{i.name}</span>)}</div>\n);\n\nThe bug is missing empty check. Fix it.' \
    512 \
    "~500 tok tool result + instrucción -> cache reuse parcial"

send "4. Long generation" \
    "Write a complete React hook useLocalStorage with TypeScript types, error handling, SSR support. Include usage example." \
    1024 \
    "Generación 1024 tok: mide t/s sostenido"

printf "\n${CYAN}${BOLD}══════════════════════════════════════════════════${RESET}\n"
printf "${BOLD}  Done${RESET}\n"
