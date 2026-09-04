# 单张 RTX 5090 部署 Qwen3.8-27B

[English](README_EN.md)

这是一套已经在单张 NVIDIA GeForce RTX 5090 32 GB 上跑通的
`Qwen3.8-27B-NVFP4 + SGLang` 部署方法。服务提供 OpenAI 兼容接口。

## 实测环境

- Ubuntu 22.04.5 LTS
- RTX 5090 32 GB，驱动 580.105.08
- Python 3.11.5
- SGLang commit：`1cf2b8c54d81802abc15dcf23a29b9cc687bc01e`
- PyTorch 2.13.0 + CUDA 13.0
- 模型：[`RadixArk/Qwen3.8-27B-NVFP4`](https://huggingface.co/RadixArk/Qwen3.8-27B-NVFP4)
- 模型 commit：`319f741cce68d7914884900c138a1fbb70a42f30`

建议准备 64 GB 主机内存和至少 45 GB 可用磁盘。其他软硬件组合没有验证。

## 1. 安装系统依赖

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl patch tar coreutils binutils python3.11-venv
```

如果 `python3.11` 不在系统路径中，也可以使用 Conda/Miniforge 的 Python 3.11。

## 2. 下载仓库并建立环境

```bash
git clone https://github.com/chrispowter/qwen38-27b-rtx5090-sglang.git
cd qwen38-27b-rtx5090-sglang
chmod +x ./*.sh
PYTHON_BIN=/path/to/python3.11 ./bootstrap.sh
```

默认部署目录为 `/data/qwen38-sglang`。需要放在其他位置时，后续所有命令都传入
相同的 `BASE_DIR`：

```bash
BASE_DIR=/your/path PYTHON_BIN=/path/to/python3.11 ./bootstrap.sh
```

## 3. 下载模型并启动

能够直接访问 Hugging Face 时：

```bash
./complete_install.sh
```

使用 ModelScope 镜像时：

```bash
DOWNLOAD_BACKEND=modelscope ./complete_install.sh
```

脚本会断点下载模型、校验 SHA-256、启动 SGLang，并等待接口就绪。查看状态与
日志：

```bash
cat /data/qwen38-sglang/run/deployment.status
tail -f /data/qwen38-sglang/logs/server.log
```

如果服务器需要使用 Windows 开发机的本地代理，可先在 Windows 运行：

```powershell
pwsh -File .\proxy_watch.ps1 `
  -SshTarget gpu-server `
  -RemotePort 17893 `
  -LocalProxyPort 7890
```

然后在服务器运行：

```bash
PROXY_URL=http://127.0.0.1:17893 \
DOWNLOAD_BACKEND=modelscope \
./complete_install.sh
```

## 4. 从开发机连接

服务默认只监听服务器回环地址 `127.0.0.1:30000`。在开发机建立 SSH 隧道：

```bash
ssh -N -L 30000:127.0.0.1:30000 gpu-server
```

本机客户端使用：

```text
http://127.0.0.1:30000/v1
```

不要把这个未鉴权端点直接暴露到公网或局域网。

## 5. 日常命令

```bash
./start_server.sh
./stop_server.sh
```

默认服务参数为 65,536 tokens 上下文、FP8 E4M3 KV cache、单并发和
`mem_fraction_static=0.86`。如需覆盖：

```bash
CONTEXT_LENGTH=65536 \
MEM_FRACTION_STATIC=0.86 \
MAX_RUNNING_REQUESTS=1 \
./start_server.sh
```

## License

本仓库代码使用 [Apache License 2.0](LICENSE)。模型权重和 SGLang 源码不在本仓库
分发，分别受其上游许可证约束。
