#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

# ============================================================
# Script: setup.sh
# Descripción: Compila llama.cpp con servidor OpenAI-compatible
#              y descarga modelo Qwen3.5-4B cuantizado
# Uso: bash ~/llama-adreno/setup.sh
# ============================================================

# Validación de entorno Termux
if [ -z "${PREFIX:-}" ]; then
    echo "Error: Este script está diseñado exclusivamente para Termux en Android." >&2
    exit 1
fi

# Registro global de limpieza
ARCHIVOS_TEMPORALES=()
DIRECTORIOS_TEMPORALES=()

limpiar_recursos() {
    local estado_salida=$?
    if [ ${#ARCHIVOS_TEMPORALES[@]} -gt 0 ]; then
        rm -f "${ARCHIVOS_TEMPORALES[@]}"
    fi
    if [ ${#DIRECTORIOS_TEMPORALES[@]} -gt 0 ]; then
        rm -rf "${DIRECTORIOS_TEMPORALES[@]}"
    fi
    exit "$estado_salida"
}

trap limpiar_recursos EXIT INT TERM

# ============================================================
# Funciones
# ============================================================

log_info() {
    echo "[INFO] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_success() {
    echo "[OK] $*" >&2
}

instalar_dependencias() {
    log_info "Verificando dependencias..."
    local deps=(
        "git:git"
        "cmake:cmake"
        "clang:clang"
        "make:make"
    )

    local pendientes=()

    for dep_entry in "${deps[@]}"; do
        local cmd="${dep_entry%%:*}"
        local pkg="${dep_entry##*:}"
        if ! command -v "$cmd" &> /dev/null; then
            pendientes+=("$pkg")
        fi
    done

    if [ ${#pendientes[@]} -gt 0 ]; then
        log_info "Instalando: ${pendientes[*]}"
        pkg install -y "${pendientes[@]}"
    else
        log_success "Todas las dependencias ya están instaladas"
    fi
}

clonar_repositorio() {
    local repo_dir="$HOME/llama-adreno/src"

    if [ -d "$repo_dir/.git" ]; then
        log_info "Repositorio ya existe, actualizando..."
        git -C "$repo_dir" pull --ff-only >/dev/null 2>&1 || git -C "$repo_dir" checkout main >/dev/null 2>&1
    else
        log_info "Clonando llama.cpp..."
        git clone --depth 1 https://github.com/ggerganov/llama.cpp.git "$repo_dir"
    fi

    echo "$repo_dir"
}

compilar_llama() {
    local repo_dir="$1"

    log_info "Creando parche spawn.h para Android..."
    mkdir -p "$repo_dir/tools/server/android"

    cat > "$repo_dir/tools/server/android/spawn.c" << 'SPAWN_C'
#include <spawn.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

int posix_spawn_file_actions_init(posix_spawn_file_actions_t *file_actions) {
    memset(file_actions, 0, sizeof(*file_actions));
    return 0;
}

int posix_spawn_file_actions_destroy(posix_spawn_file_actions_t *file_actions) {
    (void)file_actions;
    return 0;
}

int posix_spawn_file_actions_addclose(posix_spawn_file_actions_t *file_actions, int fd) {
    (void)file_actions;
    (void)fd;
    return 0;
}

int posix_spawn_file_actions_adddup2(posix_spawn_file_actions_t *file_actions,
                                     int fd, int newfd) {
    (void)file_actions;
    (void)fd;
    (void)newfd;
    return 0;
}

int posix_spawn_file_actions_addopen(posix_spawn_file_actions_t *file_actions,
                                     int fd, const char *path, int oflag, mode_t mode) {
    (void)file_actions;
    (void)fd;
    (void)path;
    (void)oflag;
    (void)mode;
    return 0;
}

int posix_spawnattr_init(posix_spawnattr_t *attr) {
    memset(attr, 0, sizeof(*attr));
    return 0;
}

int posix_spawnattr_destroy(posix_spawnattr_t *attr) {
    (void)attr;
    return 0;
}

int posix_spawnattr_setflags(posix_spawnattr_t *attr, short flags) {
    (void)attr;
    (void)flags;
    return 0;
}

int posix_spawnattr_getflags(const posix_spawnattr_t *attr, short *flags) {
    (void)attr;
    *flags = 0;
    return 0;
}

static int do_spawn(pid_t *pid, const char *path, int search_path,
                    char *const argv[], char *const envp[]) {
    pid_t child = fork();
    if (child < 0) return errno;
    if (child == 0) {
        if (search_path) {
            execvpe(path, argv, envp);
        } else {
            execve(path, argv, envp);
        }
        _exit(127);
    }
    if (pid) *pid = child;
    return 0;
}

int posix_spawn(pid_t *pid, const char *path,
                const posix_spawn_file_actions_t *file_actions,
                const posix_spawnattr_t *attrp,
                char *const argv[], char *const envp[]) {
    (void)file_actions;
    (void)attrp;
    return do_spawn(pid, path, 0, argv, envp);
}

int posix_spawnp(pid_t *pid, const char *file,
                 const posix_spawn_file_actions_t *file_actions,
                 const posix_spawnattr_t *attrp,
                 char *const argv[], char *const envp[]) {
    (void)file_actions;
    (void)attrp;
    return do_spawn(pid, file, 1, argv, envp);
}
SPAWN_C

    cat > "$PREFIX/include/spawn.h" << 'SPAWN_H'
#ifndef _SPAWN_H
#define _SPAWN_H

#include <sys/types.h>
#include <sched.h>

#define POSIX_SPAWN_RESETIDS 0x01
#define POSIX_SPAWN_SETPGROUP 0x02
#define POSIX_SPAWN_SETSIGDEF 0x04
#define POSIX_SPAWN_SETSIGMASK 0x08
#define POSIX_SPAWN_SETSCHEDPARAM 0x10
#define POSIX_SPAWN_SETSCHEDULER 0x20
#define POSIX_SPAWN_USEVFORK 0x40
#define POSIX_SPAWN_SETSID 0x80

typedef struct {
    int __reserved[8];
} posix_spawn_file_actions_t;

typedef struct {
    int __reserved[8];
} posix_spawnattr_t;

int posix_spawn(pid_t *pid, const char *path,
                const posix_spawn_file_actions_t *file_actions,
                const posix_spawnattr_t *attrp,
                char *const argv[], char *const envp[]);

int posix_spawnp(pid_t *pid, const char *file,
                 const posix_spawn_file_actions_t *file_actions,
                 const posix_spawnattr_t *attrp,
                 char *const argv[], char *const envp[]);

int posix_spawn_file_actions_init(posix_spawn_file_actions_t *file_actions);
int posix_spawn_file_actions_destroy(posix_spawn_file_actions_t *file_actions);
int posix_spawn_file_actions_addopen(posix_spawn_file_actions_t *file_actions,
                                     int fd, const char *path, int oflag, mode_t mode);
int posix_spawn_file_actions_addclose(posix_spawn_file_actions_t *file_actions, int fd);
int posix_spawn_file_actions_adddup2(posix_spawn_file_actions_t *file_actions,
                                     int fd, int newfd);
int posix_spawnattr_init(posix_spawnattr_t *attr);
int posix_spawnattr_destroy(posix_spawnattr_t *attr);
int posix_spawnattr_setflags(posix_spawnattr_t *attr, short flags);
int posix_spawnattr_getflags(const posix_spawnattr_t *attr, short *flags);

#endif
SPAWN_H

    log_info "Compilando llama.cpp con servidor OpenAI-compatible..."
    cd "$repo_dir"

    cmake -B build \
        -DCMAKE_BUILD_TYPE=Release \
        -DGGML_NATIVE=ON \
        -DLLAMA_BUILD_TESTS=OFF \
        -DLLAMA_BUILD_SERVER=ON \
        -DLLAMA_BUILD_APP=OFF

    cmake --build build --config Release -j"$(nproc)" --target llama-server --target llama-cli

    if [ -f "$repo_dir/build/bin/llama-server" ] && [ -f "$repo_dir/build/bin/llama-cli" ]; then
        log_success "Compilación exitosa (llama-server y llama-cli disponibles)"
    else
        log_error "No se encontró llama-server tras la compilación"
        exit 1
    fi
}

descargar_modelo() {
    local repo_dir="$1"
    local modelo_url="https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-1.5b-instruct-q8_0.gguf"
    local modelo_path="$HOME/llama-adreno/models"
    local modelo_file="$modelo_path/qwen2.5-coder-1.5b-instruct-q8_0.gguf"

    mkdir -p "$modelo_path"

    if [ -f "$modelo_file" ]; then
        log_success "Modelo ya descargado: $modelo_file"
    else
        log_info "Descargando modelo Qwen2.5-Coder-1.5B-Instruct Q8_0 (~1.8 GB)..."
        log_info "Esto puede tardar varios minutos dependiendo de tu conexión..."
        curl -L -# -o "$modelo_file" "$modelo_url"
        log_success "Modelo descargado en: $modelo_file"
    fi

    echo "$modelo_file"
}

crear_script_chat() {
    local repo_dir="$1"
    local modelo_path="$2"
    local chat_script="$HOME/llama-adreno/chat.sh"

    cat > "$chat_script" << CHAT_EOF
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

if [ -z "\${PREFIX:-}" ]; then
    echo "Error: Este script requiere Termux." >&2
    exit 1
fi

LLAMA_BIN="\$HOME/llama-adreno/src/build/bin/llama-cli"
MODELO="\$HOME/llama-adreno/models/Qwen3.5-4B-Q4_K_M.gguf"

if [ ! -f "\$LLAMA_BIN" ]; then
    echo "Error: llama-cli no encontrado. Ejecuta primero: bash ~/llama-adreno/setup.sh" >&2
    exit 1
fi

if [ ! -f "\$MODELO" ]; then
    echo "Error: Modelo no encontrado. Ejecuta primero: bash ~/llama-adreno/setup.sh" >&2
    exit 1
fi

"\$LLAMA_BIN" \\
    --model "\$MODELO" \\
    --threads 4 \\
    --ctx-size 16384 \\
    --temp 0.7 \\
    --top-p 0.9 \\
    --repeat-penalty 1.1 \\
    --prompt "\$*" \\
    --n-predict 512
CHAT_EOF

    chmod +x "$chat_script"
    log_success "Script de chat creado: $chat_script"
}

crear_script_server() {
    local repo_dir="$1"
    local modelo_path="$2"
    local server_script="$HOME/llama-adreno/server.sh"

    cat > "$server_script" << SERVER_EOF
#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

if [ -z "\${PREFIX:-}" ]; then
    echo "Error: Este script requiere Termux." >&2
    exit 1
fi

LLAMA_BIN="\$HOME/llama-adreno/src/build/bin/llama-server"
MODELO="\$HOME/llama-adreno/models/Qwen3.5-4B-Q4_K_M.gguf"

if [ ! -f "\$LLAMA_BIN" ]; then
    echo "Error: llama-server no encontrado." >&2
    exit 1
fi

if [ ! -f "\$MODELO" ]; then
    echo "Error: Modelo no encontrado." >&2
    exit 1
fi

echo "Iniciando servidor OpenAI-compatible en http://127.0.0.1:8080"
echo "Configura opencode con:"
echo '  "api_base": "http://127.0.0.1:8080/v1"'
echo '  "api_key": "none"'

"\$LLAMA_BIN" \\
    --model "\$MODELO" \\
    --threads 4 \\
    --ctx-size 16384 \\
    --host 127.0.0.1 \\
    --port 8080
SERVER_EOF

    chmod +x "$server_script"
    log_success "Script de servidor creado: $server_script"
}

mostrar_instrucciones() {
    local modelo_path="$1"

    echo ""
    echo "============================================================"
    echo "  Instalación completada exitosamente"
    echo "============================================================"
    echo ""
    echo "Para chatear con el modelo, ejecuta:"
    echo ""
    echo "  bash ~/llama-adreno/chat.sh \"Tu pregunta aquí\""
    echo ""
    echo "O directamente:"
    echo ""
    echo "  \$HOME/llama-adreno/src/build/bin/llama-cli \\"
    echo "    --model $modelo_path \\"
    echo "    --threads 4 \\"
    echo "    --ctx-size 16384 \\"
    echo "    --prompt \"Hola\""
    echo ""
    echo "Para iniciar un servidor HTTP:"
    echo ""
    echo "  bash ~/llama-adreno/server.sh"
    echo ""
    echo "Para conectar con opencode, agrega en tu opencode.json:"
    echo ""
    echo '  "provider": {'
    echo '    "llama.cpp": {'
    echo '      "npm": "@ai-sdk/openai-compatible",'
    echo '      "name": "llama-server (local)",'
    echo '      "options": {'
    echo '        "baseURL": "http://127.0.0.1:8080/v1"'
    echo '      },'
    echo '      "models": {'
    echo '        "qwen3.5-4b": {'
    echo '          "name": "Qwen3.5-4B (local)"'
    echo '        }'
    echo '      }'
    echo '    }'
    echo '  }'
    echo ""
    echo "Nota: llama.cpp está optimizado para CPU ARM con FMA."
    echo "      Es más rápido que Ollama gracias a mejores optimizaciones."
    echo "      Para GPU Adreno nativa, usa la app MLC Chat APK."
    echo "============================================================"
}

# ============================================================
# Ejecución principal
# ============================================================

main() {
    log_info "Iniciando instalación de llama.cpp en Termux"
    log_info "Dispositivo: $(getprop ro.product.manufacturer) $(getprop ro.product.model 2>/dev/null || echo 'Android')"

    instalar_dependencias

    local repo_dir
    repo_dir="$(clonar_repositorio)"

    compilar_llama "$repo_dir"

    local modelo_path
    modelo_path="$(descargar_modelo "$repo_dir")"

    crear_script_chat "$repo_dir" "$modelo_path"
    crear_script_server "$repo_dir" "$modelo_path"

    mostrar_instrucciones "$modelo_path"
}

main
