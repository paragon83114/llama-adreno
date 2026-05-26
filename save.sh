#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

if [ -z "${PREFIX:-}" ]; then
    echo "Error: Este script requiere Termux." >&2
    exit 1
fi

echo "El prompt cache ahora es automatico en RAM (--cache-ram 1024)."
echo "Ya no es necesario cargar/salvar manualmente."
echo ""
echo "Para ver el estado del cache:"
echo "  curl -s http://127.0.0.1:8080/slots | python3 -m json.tool"