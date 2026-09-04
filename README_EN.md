# Qwen3.8-27B NVFP4 on a single RTX 5090

This repository contains a hardware-verified recipe for serving
`RadixArk/Qwen3.8-27B-NVFP4` with SGLang on one NVIDIA GeForce RTX 5090 32 GB.
It exposes an OpenAI-compatible endpoint on loopback and validates chat
completions, tool calls, and JSON Schema constrained output.

The repository does not redistribute model weights. The checkpoint is a
third-party NVFP4 quantization of Qwen3.8-27B; both its
[model card](https://huggingface.co/RadixArk/Qwen3.8-27B-NVFP4) and the
[upstream model card](https://huggingface.co/Qwen/Qwen3.8-27B) identify the
license as Apache-2.0.

## Verified stack

- Ubuntu 22.04.5 LTS
- NVIDIA GeForce RTX 5090, 32,607 MiB; driver 580.105.08
- 64 GiB host RAM
- Python 3.11.5
- SGLang commit `1cf2b8c54d81802abc15dcf23a29b9cc687bc01e`
- PyTorch 2.13.0 with CUDA 13.0 runtime
- FlashInfer 0.6.17 and sglang-kernel 0.4.6.post1
- `RadixArk/Qwen3.8-27B-NVFP4` commit
  `319f741cce68d7914884900c138a1fbb70a42f30`

Other combinations have not been validated.

## Quick start

Install Python 3.11 plus `curl`, `tar`, `patch`, `sha256sum`, and `readelf`, then:

```bash
git clone https://github.com/chrispowter/qwen38-27b-rtx5090-sglang.git
cd qwen38-27b-rtx5090-sglang
chmod +x ./*.sh
PYTHON_BIN=/path/to/python3.11 ./bootstrap.sh
./complete_install.sh
```

The default root is `/data/qwen38-sglang`. Override it consistently with
`BASE_DIR`. To download through ModelScope instead of the commit-pinned
Hugging Face path:

```bash
DOWNLOAD_BACKEND=modelscope ./complete_install.sh
```

The SHA-256 manifest remains authoritative for either backend.

The server only listens on remote loopback. Forward it from your client:

```bash
ssh -N -L 30000:127.0.0.1:30000 gpu-server
```

Use `http://127.0.0.1:30000/v1` locally. Do not expose the unauthenticated
endpoint directly to a LAN or the Internet.

## Why the recipe is specific

The verified path aligns PyTorch's CUDA 13.0 runtime with the FlashInfer JIT
toolchain, archives stale CUDA 11-linked JIT artifacts, limits first-build
parallelism, and applies a commit-specific SM120 patch that routes per-tensor
FP8 BMM through CUTLASS instead of the cuBLAS path that failed with
`CUBLAS_STATUS_NOT_SUPPORTED` on the tested shapes.

The conservative baseline uses one running request, a 65,536-token configured
context, FP8 E4M3 KV cache, `mem_fraction_static=0.86`, and no speculative
decoding. Read the [Chinese full guide](README.md),
[methodology](docs/methodology.md), and [troubleshooting guide](docs/troubleshooting.md)
for details.

## Scope of the measurements

On 2026-09-02, a warm short completion took 0.218 s, a 20,019-prompt-token
request producing four tokens took 2.330 s, tool calls and JSON Schema output
passed, and 1,829 MiB VRAM remained after acceptance. These are machine-specific
acceptance observations, not a standardized throughput benchmark or a claim of
application-level accuracy.

Code in this repository is licensed under [Apache-2.0](LICENSE). Model weights
and SGLang source remain governed by their upstream licenses.
