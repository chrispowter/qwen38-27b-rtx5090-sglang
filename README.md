# 单张 RTX 5090 部署 Qwen3.8-27B NVFP4

[English](README_EN.md) | [故障排查](docs/troubleshooting.md) | [复现记录](docs/reproduction-record.md)

这是一套在 **单张 NVIDIA GeForce RTX 5090 32 GB** 上实机跑通的
`Qwen3.8-27B-NVFP4 + SGLang` 部署方案。它提供仅监听回环地址的 OpenAI 兼容
接口，并验证普通对话、工具调用和 JSON Schema 结构化输出。

本仓库只包含部署与验收代码，不包含模型权重。使用的
[`RadixArk/Qwen3.8-27B-NVFP4`](https://huggingface.co/RadixArk/Qwen3.8-27B-NVFP4)
是 Qwen3.8-27B 的第三方 NVFP4 量化版本，不是 RadixArk 训练的基础模型；模型页
和上游 [`Qwen/Qwen3.8-27B`](https://huggingface.co/Qwen/Qwen3.8-27B) 均标注
Apache-2.0。

## 适用范围

- Ubuntu 22.04、单张 RTX 5090 32 GB、单用户推理服务；
- 目标是先获得可复现、留有显存余量的正确基线；
- 默认 65,536 tokens 上下文、单并发、FP8 E4M3 KV cache；
- 不默认启用 MTP、DSpark 或 DFlash 推测解码。

这不是通用的多卡吞吐方案，也没有证明所有模型任务在 FP8 KV cache 下都保持
精度。接口验收通过不等于你的业务评测通过。

## 已验证环境

| 组件 | 实测值 |
| --- | --- |
| OS | Ubuntu 22.04.5 LTS |
| GPU | NVIDIA GeForce RTX 5090，32,607 MiB |
| Driver | 580.105.08 |
| 主机内存 | 64 GiB |
| Python | 3.11.5 |
| SGLang | commit `1cf2b8c54d81802abc15dcf23a29b9cc687bc01e` |
| PyTorch | 2.13.0，CUDA runtime 13.0 |
| FlashInfer | 0.6.17 |
| SGLang kernel | 0.4.6.post1 |
| 模型 | `RadixArk/Qwen3.8-27B-NVFP4` |
| 模型 commit | `319f741cce68d7914884900c138a1fbb70a42f30` |

模型约占 21 GiB，Python 环境约占 8.5 GiB。建议至少预留 45 GiB 磁盘空间。
其他驱动、操作系统、Python 或 GPU 组合尚未验证。

## 为什么要有这套脚本

RTX 5090 是 SM120/Blackwell。该组合的难点不是“能否下载模型”，而是让权重、
PyTorch CUDA runtime、FlashInfer JIT 编译器、SGLang kernel 和实际 BMM 后端保持
一致：

1. 27B 模型的 BF16 权重无法直接装入 32 GB 显存，使用 W4A4 NVFP4 checkpoint；
2. JIT 内核必须与 PyTorch 的 CUDA 13.0 runtime 对齐，不能误链接系统 CUDA 11；
3. 固定 SGLang commit 上，SM120 的 per-tensor FP8 BMM 需要从 cuBLAS 改走
   FlashInfer CUTLASS，否则实测会触发 `CUBLAS_STATUS_NOT_SUPPORTED`；
4. 首次 Blackwell kernel 编译很吃主机内存，因此把 `MAX_JOBS` 限为 2；
5. 先关闭 prefill CUDA Graph、限制单并发和静态显存比例，再单独评估优化项。

设计取舍和故障链见 [部署方法](docs/methodology.md)。

## 快速开始

### 1. 准备系统

要求 Linux、可用的 NVIDIA 驱动、Python 3.11，以及 `curl`、`tar`、`patch`、
`sha256sum`、`readelf`。Ubuntu 上后四项通常来自以下软件包：

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl patch tar coreutils binutils python3.11-venv
```

如果系统没有合适的 `python3.11`，可使用 Conda/Miniforge 中的 Python 3.11，
并通过 `PYTHON_BIN=/path/to/python` 传入；实测使用 Python 3.11.5。

### 2. 建立锁定环境

```bash
git clone https://github.com/chrispowter/qwen38-27b-rtx5090-sglang.git
cd qwen38-27b-rtx5090-sglang
chmod +x ./*.sh
PYTHON_BIN=/path/to/python3.11 ./bootstrap.sh
```

`bootstrap.sh` 会下载并校验固定 SGLang 源码快照，建立 venv，安装实测依赖锁，
以 editable 方式安装 SGLang，并幂等应用 SM120 补丁。默认部署根目录是
`/data/qwen38-sglang`，可用 `BASE_DIR` 覆盖。

### 3. 下载模型并启动

能够直接访问 Hugging Face 时：

```bash
./complete_install.sh
cat /data/qwen38-sglang/run/deployment.status
tail -f /data/qwen38-sglang/logs/server.log
```

脚本按固定 Hugging Face commit 下载，并用 `model.sha256` 校验全部运行文件。
如果网络中断，会断点续传并重试。

使用 ModelScope 镜像时：

```bash
DOWNLOAD_BACKEND=modelscope ./complete_install.sh
```

ModelScope 只能按镜像 revision 下载，所以最终仍以本仓库 SHA-256 清单作为内容
真值；哈希不一致时不要跳过校验。

### 4. Windows 代理转发（可选）

若服务器只能借助 Windows 开发机上的本地代理联网，先在 Windows 配置好 SSH
别名 `gpu-server`，然后运行：

```powershell
pwsh -File .\proxy_watch.ps1 `
  -SshTarget gpu-server `
  -RemotePort 17893 `
  -LocalProxyPort 7890
```

远端另一个终端执行：

```bash
PROXY_URL=http://127.0.0.1:17893 \
DOWNLOAD_BACKEND=modelscope \
./complete_install.sh
```

反向隧道只绑定服务器回环地址，并在部署完成或失败后退出。

### 5. 本机访问

服务默认只监听服务器的 `127.0.0.1:30000`。从开发机建立 SSH 隧道：

```bash
ssh -N -L 30000:127.0.0.1:30000 gpu-server
```

本机客户端使用 `http://127.0.0.1:30000/v1`。不要为了省去隧道而把未鉴权端点
直接暴露到公网或实验室网段。

## 日常操作

```bash
./verify_environment.sh
./verify_model.sh
./start_server.sh
./acceptance_test.py
./stop_server.sh
```

常用覆盖项：

```bash
CONTEXT_LENGTH=65536 \
MEM_FRACTION_STATIC=0.86 \
MAX_RUNNING_REQUESTS=1 \
MAX_JOBS=2 \
./start_server.sh
```

修改任何覆盖项时应连同模型 commit、SGLang commit 和验收结果一起记录。

## 实测结果

2026-09-02 的暖机后单请求记录：

| 验收项 | 结果 |
| --- | --- |
| 模型列表与普通短回答 | 通过；固定短回答 0.218 秒 |
| 工具调用 | 通过；标准 `tool_calls` 和 `finish_reason=tool_calls` |
| JSON Schema 输出 | 通过 |
| 20,019 prompt tokens | 通过；端到端 2.330 秒，生成 4 tokens |
| 显存余量 | 验收后 1,829 MiB 空闲 |

这些是一次具体机器和短输出场景的验收记录，不是标准吞吐 benchmark，不能外推
到并发、长生成、多模态或业务精度。SGLang 当时报告的 KV 容量为 185,018 tokens，
它是分配器容量，不是本方案配置的 65,536 token 服务上限。

## 安全与质量边界

- 默认回环监听，没有内置 API 鉴权；远程访问使用 SSH 隧道。
- `--trust-remote-code` 只应配合已审查并固定 commit/hash 的模型使用。
- FP8 KV cache 会提示缺少独立 scale 并采用 1.0。该配置通过接口验收，但仍应在
  自己的冻结评测集上与 BF16 KV 对比。
- 模型可能输出错误内容。工具调用格式正确不代表工具行为安全。
- 模型和 SGLang 的许可证、限制及安全建议以各自上游仓库为准。

## 许可证

本仓库代码使用 [Apache License 2.0](LICENSE)。模型权重和 SGLang 源码不在本仓库
分发，分别受其上游许可证约束；详见 [第三方声明](THIRD_PARTY_NOTICES.md)。
