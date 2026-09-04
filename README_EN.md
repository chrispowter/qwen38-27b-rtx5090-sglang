# Deploy Qwen3.8-27B on a single RTX 5090

[中文](README.md)

This is a hardware-verified deployment recipe for serving
`Qwen3.8-27B-NVFP4` with SGLang on one NVIDIA GeForce RTX 5090 32 GB. The
service exposes an OpenAI-compatible API with chat completion, tool calling,
and JSON Schema structured output support.

## Verified environment

- Ubuntu 22.04.5 LTS
- RTX 5090 32 GB with driver 580.105.08
- Python 3.11.5
- SGLang commit `1cf2b8c54d81802abc15dcf23a29b9cc687bc01e`
- PyTorch 2.13.0 with CUDA 13.0
- Model: [`RadixArk/Qwen3.8-27B-NVFP4`](https://huggingface.co/RadixArk/Qwen3.8-27B-NVFP4)
- Model commit `319f741cce68d7914884900c138a1fbb70a42f30`

64 GB of host RAM and at least 45 GB of free disk space are recommended. Other
software and hardware combinations have not been tested.

## 1. Install system dependencies

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl patch tar coreutils binutils python3.11-venv
```

You can also use Python 3.11 from Conda or Miniforge.

## 2. Create the environment

```bash
git clone https://github.com/chrispowter/qwen38-27b-rtx5090-sglang.git
cd qwen38-27b-rtx5090-sglang
chmod +x ./*.sh acceptance_test.py
PYTHON_BIN=/path/to/python3.11 ./bootstrap.sh
```

The default deployment root is `/data/qwen38-sglang`. To use another path,
pass the same `BASE_DIR` to all commands:

```bash
BASE_DIR=/your/path PYTHON_BIN=/path/to/python3.11 ./bootstrap.sh
```

## 3. Download the model and start SGLang

With direct Hugging Face access:

```bash
./complete_install.sh
```

With the ModelScope mirror:

```bash
DOWNLOAD_BACKEND=modelscope ./complete_install.sh
```

The script resumes interrupted downloads, checks every model file against the
SHA-256 manifest, starts SGLang, and validates chat, tool calls, and JSON Schema
output. Check deployment state and logs with:

```bash
cat /data/qwen38-sglang/run/deployment.status
tail -f /data/qwen38-sglang/logs/server.log
```

If the server must use a proxy running on a Windows development machine, run on
Windows:

```powershell
pwsh -File .\proxy_watch.ps1 `
  -SshTarget gpu-server `
  -RemotePort 17893 `
  -LocalProxyPort 7890
```

Then run on the server:

```bash
PROXY_URL=http://127.0.0.1:17893 \
DOWNLOAD_BACKEND=modelscope \
./complete_install.sh
```

## 4. Connect from the development machine

The server binds only to `127.0.0.1:30000`. Create an SSH tunnel:

```bash
ssh -N -L 30000:127.0.0.1:30000 gpu-server
```

Use `http://127.0.0.1:30000/v1` from the local client. Do not expose this
unauthenticated endpoint directly to a LAN or the Internet.

## 5. Daily commands

```bash
./start_server.sh
./acceptance_test.py
./stop_server.sh
```

The default configuration uses a 65,536-token context, FP8 E4M3 KV cache, one
running request, and `mem_fraction_static=0.86`. Override it when needed:

```bash
CONTEXT_LENGTH=65536 \
MEM_FRACTION_STATIC=0.86 \
MAX_RUNNING_REQUESTS=1 \
./start_server.sh
```

On 2026-09-02, the verified machine passed chat, tool calling, JSON Schema, and
a 20k-token input test with about 1.8 GB VRAM left after acceptance. API
compatibility does not establish application-level accuracy; run your own
evaluation set before production use.

## License

Code in this repository is licensed under the [Apache License 2.0](LICENSE).
Model weights and SGLang source are not redistributed and remain governed by
their upstream licenses.
