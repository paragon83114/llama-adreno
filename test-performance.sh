#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ENDPOINT="http://127.0.0.1:8080/v1/chat/completions"

generate_tokens() {
    local n=$1
    local text=""
    for i in $(seq 1 $((n / 10))); do
        text+="This is test sentence number $i for performance testing. "
    done
    echo "$text"
}

test_request() {
    local name=$1
    local prompt=$2
    local max_tokens=${3:-100}
    
    printf "\n=== %s ===\n" "$name"
    printf "Prompt length: ~%d chars\n" "${#prompt}"
    
    local start=$(date +%s%N)
    local response=$(curl -s -X POST "$ENDPOINT" \
        -H "Content-Type: application/json" \
        -d "{
            \"model\": \"qwen2.5-coder-1.5b\",
            \"messages\": [{\"role\": \"user\", \"content\": $(echo "$prompt" | jq -Rs .)}],
            \"max_tokens\": $max_tokens,
            \"temperature\": 0.1
        }")
    local end=$(date +%s%N)
    
    local elapsed=$(( (end - start) / 1000000 ))
    local tokens=$(echo "$response" | jq -r '.usage.total_tokens // 0')
    local prompt_tokens=$(echo "$response" | jq -r '.usage.prompt_tokens // 0')
    local completion_tokens=$(echo "$response" | jq -r '.usage.completion_tokens // 0')
    
    printf "Time: %d ms\n" "$elapsed"
    printf "Tokens: %d prompt + %d completion = %d total\n" "$prompt_tokens" "$completion_tokens" "$tokens"
    
    if [ "$completion_tokens" -gt 0 ]; then
        local tps=$((completion_tokens * 1000 / elapsed))
        printf "Speed: ~%d tokens/sec (generation only)\n" "$tps"
    fi
    
    echo "$response" | jq -r '.choices[0].message.content // "ERROR"' | head -c 200
    printf "\n"
}

printf "=== Performance Test Suite ===\n"
printf "Server: http://127.0.0.1:8080\n"
printf "Date: $(date)\n"

PROMPT_2K=$(generate_tokens 2000)

test_request "Test 1: Cold Start (~2000 tokens)" "$PROMPT_2K" 50

test_request "Test 2: Warm (same prompt)" "$PROMPT_2K" 50

PROMPT_2K_EXTENDED="${PROMPT_2K} Now please summarize the key points from the text above."
test_request "Test 3: Extended prompt (cache-reuse)" "$PROMPT_2K_EXTENDED" 100

test_request "Test 4: Small prompt (baseline)" "Hello, how are you?" 50

printf "\n=== Tests Complete ===\n"
