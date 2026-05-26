# Running llama.cpp with Adreno 830 GPU acceleration on Termux (Snapdragon 8 Elite)

I got llama.cpp's OpenCL backend running on Qualcomm's Adreno 830 GPU inside Termux, on a Xiaomi Pad 8 Pro (Snapdragon 8 Elite). This is the first documented setup for this GPU.

## Why this matters

llama.cpp has OpenCL support, but on Android the Adreno OpenCL driver lives in `/vendor/lib64/`, which is invisible to Termux's linker. Making it work requires:

- An ICD entry pointing to `/vendor/lib64/libOpenCL_adreno.so`
- `LD_LIBRARY_PATH=/vendor/lib64` at runtime for the driver's dependencies (`libcutils.so`, `libvndksupport.so`)
- Building with `GGML_OPENCL_USE_ADRENO_KERNELS=ON`
- Using `f16` KV cache (not `q8_0`, which crashes OpenCL's `SET_ROWS`)

## Benchmark results

**Qwen2.5-Coder-1.5B-Instruct Q8_0 on Adreno 830:**

| Config | pp512 (t/s) | tg128 (t/s) |
|--------|-------------|-------------|
| GPU ngl=99, f16 KV, 6t | **579** | **21.3** |
| CPU-only 6t, q8_0 KV | 24.17 | 7.95 |

That's a **24x prefill speedup** and **2.7x token generation speedup** compared to CPU-only on this model.

**Qwen2.5-Coder-7B Q4_K_M (for comparison):**

| Config | pp512 (t/s) | tg128 (t/s) |
|--------|-------------|-------------|
| GPU ngl=99, f16 KV | **89.19** | 6.60 |
| CPU-only 6t, q8_0 KV | 24.17 | 7.95 |

For the 7B model, GPU gives 3.7x prefill speedup but ~17% slower tg due to CPU-GPU sync overhead per token.

## Key findings

- **6 threads pinned to performance cores** (`-C 0x3f`) is optimal — 8 threads causes 55% tg regression on Snapdragon 8 Elite's asymmetric Oryon cores
- **f16 KV cache is required** with OpenCL — `q8_0` triggers `SET_ROWS` crash ([issue #21501](https://github.com/ggml-org/llama.cpp/issues/21501))
- **Flash attention is disabled** when `-ngl > 0` on OpenCL
- **`--mlock` causes OOM** with GPU offload on 12 GB RAM
- ARM arch flags `armv8.6-a+dotprod+fp16+i8mm` + KleidiAI provide meaningful CPU-side speedups

## Full setup

Everything is packaged with ready-to-use scripts:

**GitHub: [paragon83114/llama-adreno](https://github.com/paragon83114/llama-adreno)**

```bash
git clone https://github.com/paragon83114/llama-adreno.git
cd llama-adreno
bash setup.sh    # installs deps, builds llama.cpp with Adreno OpenCL, downloads model
bash server.sh   # starts llama-server with GPU+CPU hybrid config
```

The repo includes `server.sh`, `chat.sh`, `download-model.sh`, KV cache management scripts, and detailed documentation in the README.

## Looking forward

PR #23501 (Qualcomm) adds flash attention, K-split, and `q4_0` KV for Adreno — should significantly improve tg performance once merged.

Tested on: Xiaomi Pad 8 Pro, Snapdragon 8 Elite (SM8750P), 12 GB RAM, Adreno 830, Android 15, Termux (F-Droid).