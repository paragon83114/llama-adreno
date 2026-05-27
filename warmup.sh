#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

if [ -z "${PREFIX:-}" ]; then
    printf "\033[1;31m✗ Este script requiere Termux.\033[0m\n" >&2
    exit 1
fi

BOLD="\033[1m"; GREEN="\033[1;32m"; YELLOW="\033[1;33m"; CYAN="\033[1;36m"; RED="\033[1;31m"; RESET="\033[0m"

SYS_PROMPT="You are an expert software engineer. You have access to a codebase and can read files, run commands, and make changes.

When asked to help with code:
1. Read the relevant files to understand the current implementation
2. Make the necessary changes
3. Explain what you changed and why

Always provide complete, working code."

printf "\n${CYAN}${BOLD}▗▖▗▗▖▗▖▘▐ ${RESET}${BOLD}llama-server warmup${RESET}\n\n"

if ! curl -sf http://127.0.0.1:8080/health > /dev/null 2>&1; then
    printf "${YELLOW}⟳${RESET} Servidor no detectado — iniciando server.sh...\n"
    bash "$HOME/llama-adreno/server.sh" > /dev/null 2>&1 &
    for i in $(seq 1 60); do
        if curl -sf http://127.0.0.1:8080/health > /dev/null 2>&1; then
            printf "  ${GREEN}✓${RESET} Servidor listo tras ${i}s\n"
            break
        fi
        sleep 1
    done
else
    printf "${GREEN}✓${RESET} Servidor ya está corriendo\n"
fi

printf "${YELLOW}⟳${RESET} Calentando prompt cache..."
RESP=$(curl -s --max-time 300 -X POST http://127.0.0.1:8080/v1/chat/completions \
    -H "Content-Type: application/json" \
    -d "$(jq -n --arg sys "$SYS_PROMPT" --arg msg "What files are in the src directory?" '{
        model: "qwen2.5-coder-1.5b",
        messages: [{role: "system", content: $sys}, {role: "user", content: $msg}],
        max_tokens: 64,
        temperature: 0.1
    }')")

if echo "$RESP" | jq -e '.error' > /dev/null 2>&1; then
    printf "${RED}✗${RESET} Error en warmup: %s\n" "$(echo "$RESP" | jq -r '.error.message')"
    exit 1
fi

PT=$(echo "$RESP" | jq -r '.usage.prompt_tokens // 0')
CT=$(echo "$RESP" | jq -r '.usage.completion_tokens // 0')
printf "\n${GREEN}✓${RESET} Cache cálido — %d tok prompt + %d completion\n" "$PT" "$CT"

curl -s -X POST "http://127.0.0.1:8080/slots/0?action=save" \
    -H "Content-Type: application/json" \
    -d '{"filename": "slot0.bin"}' > /dev/null 2>&1 || true

printf "\n${GREEN}${BOLD}✓ Servidor listo — abre opencode${RESET}\n"