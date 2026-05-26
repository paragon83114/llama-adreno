# llama-adreno — Termux llama.cpp with Adreno GPU acceleration

## What this is

A wrapper around llama.cpp for running LLMs locally on Android/Termux with Adreno 830 GPU acceleration. **Not** the llama.cpp source repo itself — that lives in `src/` as a shallow git clone.

## Directory layout

- `setup.sh` — one-time bootstrap: installs deps, clones llama.cpp into `src/`, builds binaries, downloads Qwen2.5-Coder-1.5B-Instruct Q8_0 model.
- `download-model.sh` — standalone script to download the model. Called by `setup.sh` and referenced in error messages if the model is missing.
- `server.sh` — starts `llama-server` with GPU+CPU hybrid (Adreno 830 + 4 CPU threads), f16 KV cache, `-ngl 99`, batch 2048, ctx 16384. Auto-saves KV cache on Ctrl+C. Requires `LD_LIBRARY_PATH` to find Adreno OpenCL driver.
- `chat.sh` — interactive CLI chat with same GPU+CPU config but ctx-size 32764.
- `load.sh` / `save.sh` — manual KV cache restore/save via the server HTTP API. **Requires `server.sh` to be running first.**
- `models/` — GGUF model files. Active model: `qwen2.5-coder-1.5b-instruct-q8_0.gguf` (~1.76 GiB).
- `cache/` — KV cache (`slot0.bin`). Auto-loaded on server start, auto-saved on server stop. f16 format.
- `logs/` — server log files with symlink `server-latest.log`.
- `backup/` — pre-OpenCL CPU-only binaries and scripts snapshot.
- `src/` — llama.cpp git clone. Built binaries at `src/build/bin/llama-server` and `src/build/bin/llama-cli`.

## Key constraints

- **Termux-only**: all scripts enforce `$PREFIX` check. Do not remove.
- **posix_spawn polyfill**: `setup.sh` writes `spawn.h` to `$PREFIX/include/` and `spawn.c` to `src/tools/server/android/` because Android/Termux lacks posix_spawn. Needed for the server to compile.
- **Server must be running** before `save.sh`/`load.sh`/any API calls can work.
- **Model path is hardcoded** in `server.sh` and `chat.sh` — changing models requires editing both scripts.
- Server listens on `http://127.0.0.1:8080`; OpenAI-compatible endpoint: `http://127.0.0.1:8080/v1`.
- **KV cache format**: must match `-ctk`/`-ctv` flags. Currently f16. Do not mix with `q8_0`.
- **OpenCL requires `LD_LIBRARY_PATH`**: scripts inject `/vendor/lib64` so the ICD loader can find `libOpenCL_adreno.so`. Without it, only the clvk/llvmpipe CPU emulator is available.

## GPU acceleration (Adreno 830)

The build includes `GGML_OPENCL=ON` with `GGML_OPENCL_USE_ADRENO_KERNELS=ON`. The Adreno 830 is detected via an ICD entry at `$PREFIX/etc/OpenCL/vendors/adreno.icd`.

**Benchmark results (Qwen2.5-Coder-1.5B-Instruct Q8_0, build 549b9d8):**

| Config | pp512 (t/s) | tg128 (t/s) |
|--------|-------------|--------------|
| GPU ngl=99, f16 KV, 4t (cores 0-3) | 562 ± 12 | 31.4 ± 0.0 |
| GPU ngl=99, f16 KV, 2t (cores 0-1) | 571 ± 4 | 31.1 ± 0.1 |
| GPU ngl=99, f16 KV, 6t (cores 0-5) | 561 ± 13 | 30.5 ± 1.5 |

| Config | pp1280 (t/s) | pp2048 (t/s) | tg256 (t/s) |
|--------|-------------|--------------|-------------|
| GPU ngl=99, f16 KV, 4t | 507 ± 9 | 460 ± 3 | 26.6 ± 0.1 |

| Config | pp512 (t/s) | tg128 (t/s) |
|--------|-------------|--------------|
| CPU-only 6t, q8_0 KV, flash attn | 24.17 | **7.95** |
| GPU ngl=99, f16 KV (7B model) | **89.19** | 6.60 |
| GPU ngl=10, f16 KV (7B model) | 28.63 | 6.82 |

- GPU offload gives major prefill speedup on all model sizes
- **KV cache must be f16** with GPU offload — `q8_0` causes a `SET_ROWS` crash on the OpenCL backend.
- **Flash attention is disabled** automatically when `-ngl > 0` (OpenCL backend limitation).

**OpenCL setup details:**
- ICD file: `$PREFIX/etc/OpenCL/vendors/adreno.icd` → `/vendor/lib64/libOpenCL_adreno.so`
- The driver at `/vendor/lib64/` is inaccessible from Termux's linker namespace. `LD_LIBRARY_PATH=/vendor/lib64` is required at runtime for the driver's own dependencies (`libcutils.so`, `libvndksupport.so`).
- `clinfo -l` should show `QUALCOMM Adreno(TM) 830` when config is correct. If it shows only `llvmpipe`, the ICD is missing or `LD_LIBRARY_PATH` is wrong.

## Build configuration

Current cmake flags (as of latest rebuild):

```
-DGGML_NATIVE=OFF
-DGGML_CPU_ARM_ARCH=armv8.6-a+dotprod+fp16+i8mm
-DGGML_CPU_KLEIDIAI=ON
-DGGML_LTO=ON
-DGGML_LLAMAFILE=ON
-DGGML_OPENMP=ON
-DGGML_CPU_REPACK=ON
-DGGML_OPENCL=ON
-DGGML_OPENCL_USE_ADRENO_KERNELS=ON
-DOpenCL_LIBRARY=$PREFIX/lib/libOpenCL.so   # ICD loader, not vendor driver
-DCMAKE_BUILD_TYPE=Release
-DLLAMA_BUILD_TESTS=OFF
-DLLAMA_BUILD_SERVER=ON
-DLLAMA_BUILD_APP=OFF
```

Binaries are shared libs (`libggml-opencl.so.*`, `libggml-cpu.so.*`, etc.) with RUNPATH set to `src/build/bin`.

## Threading

Snapdragon 8 Elite (SM8750P) has 8 Oryon cores: 2 Prime (4.47 GHz) + 6 Performance (3.53 GHz). Using 8 threads causes ~55% regression in token generation due to cross-cluster synchronization. **4 threads pinned to cores 0-3 (`-C 0xf`) is optimal** — sufficient for KV cache ops alongside GPU, leaves cores free for the system, and avoids cross-cluster latency variance seen with 6 threads.

## Rebuilding

If `src/` needs recompilation:

```bash
bash ~/llama-adreno/setup.sh  # full rebuild (re-clones if needed) — WARNING: overwrites manual cmake flags
# Or manual (current optimized config):
cd ~/llama-adreno/src && cmake -B build \
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
  -DOpenCL_LIBRARY=$PREFIX/lib/libOpenCL.so \
  -DLLAMA_BUILD_TESTS=OFF \
  -DLLAMA_BUILD_SERVER=ON \
  -DLLAMA_BUILD_APP=OFF
cmake --build build --config Release -j$(nproc) --target llama-server --target llama-cli --target llama-bench
```

## Restoring backup

If the OpenCL build causes issues, the CPU-only backup exists at `~/llama-adreno/backup/`:

```bash
cp ~/llama-adreno/backup/llama-server ~/llama-adreno/src/build/bin/
cp ~/llama-adreno/backup/llama-cli ~/llama-adreno/src/build/bin/
cp ~/llama-adreno/backup/lib*.so* ~/llama-adreno/src/build/bin/
# And revert server.sh/chat.sh to CPU-only (remove -ngl, revert -ctk/-ctv to q8_0, remove LD_LIBRARY_PATH)
cp ~/llama-adreno/backup/server.sh ~/llama-adreno/server.sh
cp ~/llama-adreno/backup/chat.sh ~/llama-adreno/chat.sh
rm -f ~/llama-adreno/cache/slot0.bin  # KV cache format changed
```

## Upstream AGENTS.md

`src/AGENTS.md` is the upstream llama.cpp project's AI contribution policy. It applies to PRs made to the llama.cpp repo, not to changes in this wrapper project.