#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

if [ -z "${PREFIX:-}" ]; then
    echo "Error: Este script requiere Termux." >&2
    exit 1
fi

echo "Restaurando caché del prompt del servidor..."

curl -X POST "http://127.0.0.1:8080/slots/0?action=restore" \
     -H "Content-Type: application/json" \
     -d '{"filename": "slot0.bin"}'

echo ""
echo "[OK] Caché de contexto restaurado con éxito desde ~/llama-adreno/cache/slot0.bin"
