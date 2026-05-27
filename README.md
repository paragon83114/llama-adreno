# llama-adreno

Run LLMs locally on Android with **Adreno 830 GPU acceleration** via llama.cpp + OpenCL on Termux.

This is the first documented setup running llama.cpp's OpenCL backend on Qualcomm's Adreno 830 (Snapdragon 8 Elite), achieving **663 t/s prefill** and **44.8 t/s token generation** with Qwen2.5-Coder-1.5B-Instruct Q4_0 on a tablet.

## Why this exists

llama.cpp supports OpenCL, but getting it to work on Android's Adreno GPU is non-trivial:

- The Adreno OpenCL driver lives in `/vendor/lib64/`, outside Termux's linker namespace
- `LD_LIBRARY_PATH` must be injected for the ICD loader to find the driver's dependencies
- A custom ICD entry is needed at `$PREFIX/etc/OpenCL/vendors/adreno.icd`
- `q8_0` KV cache crashes the OpenCL backend (`SET_ROWS` bug — see [issue #21501](https://github.com/ggml-org/llama.cpp/issues/21501))
- Flash attention is disabled when `-ngl > 0` on OpenCL
- Using 8 threads on Snapdragon 8 Elite causes 55% regression in tg due to cross-cluster synchronization

This project packages all that knowledge into ready-to-use scripts.

## Benchmark results

**Qwen2.5-Coder-1.5B-Instruct Q4_0 — Adreno 830 GPU offload (Snapdragon 8 Elite)**

| Test | t/s |
|:----:|:---:|
| pp512 | **663 ± 11** |
| pp2048 | **535 ± 13** |
| tg128 | **44.8 ± 0.2** |
| tg256 | **39.4 ± 4.6** |

Q4_0 es el formato óptimo para el backend OpenCL de Adreno — Qualcomm lo ha optimizado específicamente. Ver benchmarks comparativos con Q8_0 y Q4_K_M en [AGENTS.md](AGENTS.md).

CPU-only comparison:

| Config | pp512 (t/s) | tg128 (t/s) |
|--------|-------------|-------------|
| CPU-only 6t, q8_0 KV, flash attn | 24.17 | 7.95 |

**Qwen2.5-Coder-7B-Instruct Q4_K_M — Adreno 830 GPU offload**

| Config | pp512 (t/s) | tg128 (t/s) |
|--------|-------------|-------------|
| GPU ngl=99, f16 KV | **89.19** | 6.60 |
| GPU ngl=10, f16 KV | 28.63 | 6.82 |

Key takeaway: GPU offload gives **27x prefill speedup** over CPU-only. 4 threads is optimal — avoids cross-cluster latency while providing stable token generation.
- **Prompt cache**: with `--cache-ram 1024`, subsequent requests with the same system prompt are **~240x faster** (0.1s vs 25s prefill), essential for interactive code assistants.

## Quick start

### Prerequisites

- Android device with Adreno 830+ GPU (Snapdragon 8 Elite / SM8750P)
- [Termux](https://termux.dev/) installed
- ~3 GB free storage (model + build artifacts)

### 1. Bootstrap

```bash
git clone https://github.com/paragon83114/llama-adreno.git
cd llama-adreno
bash setup.sh
```

This installs dependencies, clones llama.cpp, builds binaries with Adreno OpenCL support, and downloads the model.

### 2. Download the model (if not using setup.sh)

```bash
bash download-model.sh
```

Or manually:

```bash
curl -L -o models/qwen2.5-coder-1.5b-instruct-q4_0.gguf \
  "https://huggingface.co/Qwen/Qwen2.5-Coder-1.5B-Instruct-GGUF/resolve/main/qwen2.5-coder-1.5b-instruct-q4_0.gguf"
```

### 3. Start the server

```bash
bash server.sh
```

The server starts at `http://127.0.0.1:8080` with an OpenAI-compatible API at `/v1`. Tras el primer request, el prompt cache acelera requests subsecuentes ~240x.

### 4. Chat interactively

```bash
bash chat.sh
```

## Scripts

| Script | Description |
|--------|-------------|
| `setup.sh` | One-time bootstrap: deps, build, model download |
| `download-model.sh` | Standalone model download script |
| `server.sh` | Start llama-server with GPU+CPU hybrid config |
| `chat.sh` | Interactive CLI chat with same GPU config |
| `save.sh` | Save KV cache to disk (requires running server) |
| `load.sh` | Restore KV cache from disk (requires running server) |

## How it works

### OpenCL on Adreno

The Adreno OpenCL driver is accessible from Android's vendor partition but invisible to Termux's linker. Three things make it work:

1. **ICD entry** — `$PREFIX/etc/OpenCL/vendors/adreno.icd` pointing to `/vendor/lib64/libOpenCL_adreno.so`
2. **ICD loader** — Termux's `libOpenCL.so` (ocl-icd) reads the ICD entry at runtime
3. **LD_LIBRARY_PATH** — `/vendor/lib64` is prepended so the driver finds its own dependencies (`libcutils.so`, `libvndksupport.so`)

Verify with:
```bash
LD_LIBRARY_PATH=/vendor/lib64 clinfo -l
# Should show: QUALCOMM Adreno(TM) 830
```

### Threading

Snapdragon 8 Elite has 8 Oryon cores: 2 Prime (4.47 GHz) + 6 Performance (3.53 GHz). Benchmarks show thread count barely impacts prefill with GPU offload, but more threads add variance to token generation due to cross-cluster synchronization. **4 threads pinned to cores 0-3 (`-C 0xf`) is optimal** — stable tg, leaves cores free for the system.

### Build flags (current optimized config)

```bash
cmake -B build \
  -DCMAKE_BUILD_TYPE=Release \
  -DGGML_NATIVE=OFF \
  -DGGML_CPU_ARM_ARCH=armv8.6-a+dotprod+fp16+i8mm \
  -DGGML_CPU_KLEIDIAI=ON \
  -DGGML_LTO=ON \
  -DGGML_LLAMAFILE=ON \
  -DGGML_OPENMP=ON \
  -DGGML_CPU_REPACK=ON \
  -DGGML_OPENCL=ON \
  -DGGML_OPENCL_USE_ADRENO_KERNELS=ON \
  -DGGML_SCHED_NO_REALLOC=ON \
  -DOpenCL_LIBRARY=$PREFIX/lib/libOpenCL.so \
  -DLLAMA_BUILD_TESTS=OFF \
  -DLLAMA_BUILD_SERVER=ON \
  -DLLAMA_BUILD_APP=OFF \
  -DLLAMA_BUILD_UI=OFF \
  -DLLAMA_OPENSSL=OFF
```

ARM architecture flags (`dotprod`, `fp16`, `i8mm`) and KleidiAI provide significant CPU-side speedups. `GGML_OPENCL_USE_ADRENO_KERNELS=ON` enables Qualcomm-optimized kernel paths. `GGML_SCHED_NO_REALLOC=ON` mejora token generation +16%.

### posix_spawn polyfill

Android/Termux lacks `posix_spawn`. `setup.sh` writes a compatibility shim (`spawn.h` → `$PREFIX/include/`, `spawn.c` → `src/tools/server/android/`) so `llama-server` can compile.

### KV cache & prompt cache

- **Format**: f16 (required for OpenCL — `q8_0` triggers `SET_ROWS` crash)
- **Auto-save**: `server.sh` saves KV cache on Ctrl+C (SIGINT handler)
- **Auto-load**: Server loads existing cache on startup
- **Prompt cache**: enabled with `--cache-ram 1024`. Tras el primer request con system prompt, los siguientes son ~240x más rápidos (0.1s vs 25s).
- **Manual**: Use `save.sh` / `load.sh` while the server is running

## Known limitations

| Limitation | Details |
|-----------|---------|
| `q8_0` KV cache crash | OpenCL backend `SET_ROWS` bug — [issue #21501](https://github.com/ggml-org/llama.cpp/issues/21501) |
| No flash attention with `-ngl > 0` | OpenCL backend limitation |
| tg regression on larger models | CPU-GPU sync overhead per token; mitigated on smaller models |
| `--mlock` OOM | Causes OOM with GPU offload on 12 GB RAM |
| posix_spawn missing | Requires manual polyfill for `llama-server` compilation |
| Moving directory after build | Binaries have RUNPATH hardcoded at compile time — **recompile** or fix with `patchelf --set-rpath` |
| `--parallel > 1` degrades tg | Adreno 830 cannot run concurrent OpenCL kernels — single slot with prompt cache is optimal |

## Upcoming improvements

- Vulkan backend for Adreno is another potential path for better tg performance

## Project structure

```
llama-adreno/
├── server.sh          # Start GPU+CPU hybrid server
├── chat.sh            # Interactive CLI chat
├── load.sh            # Restore KV cache
├── save.sh            # Save KV cache
├── setup.sh           # One-time bootstrap
├── download-model.sh  # Download model standalone
├── opencode.json      # OpenCode config for local server
├── AGENTS.md          # AI agent context
├── models/            # GGUF model files (gitignored)
├── cache/             # KV cache (gitignored)
├── logs/              # Server logs (gitignored)
├── backup/            # CPU-only fallback (gitignored)
└── src/               # llama.cpp source (gitignored)
```

## Hardware

Tested on:
- **Xiaomi Pad 8 Pro** — Snapdragon 8 Elite (SM8750P), 12 GB RAM, Adreno 830
- Android 15, Termux from F-Droid

## License

This wrapper project is provided as-is. llama.cpp is licensed under its own terms (see `src/` if cloned).

## Acknowledgments

- [llama.cpp](https://github.com/ggml-org/llama.cpp) — the underlying inference engine
- Qualcomm Adreno OpenCL driver — shipped with Android, made accessible via ICD configuration
- [ocl-icd](https://github.com/OCL-dev/ocl-icd) — OpenCL ICD loader used in Termux