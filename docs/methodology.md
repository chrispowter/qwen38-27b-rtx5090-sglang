# 部署方法：从约束到可复现基线

## 1. 先定义问题

目标不是追求最高公开 benchmark，而是在单张 32 GB RTX 5090 上建立一个：

- 能装下 27B 模型；
- 能稳定启动和重启；
- 能通过 OpenAI 兼容接口提供普通对话、工具调用与结构化输出；
- 能识别环境漂移和模型文件漂移；
- 默认不暴露未鉴权网络端口；
- 留有足够显存和主机内存余量；
- 后续可用业务评测判断质量，而不是把“服务启动”当成模型正确。

## 2. 显存约束决定量化路线

27B 参数若按 BF16 粗略估算，仅权重就超过 50 GB，尚未计算 KV cache、激活与
运行时工作区，因此不可能直接作为单卡 32 GB 基线。实测方案选用第三方 W4A4
NVFP4 checkpoint；模型目录约 21 GiB，使权重与有限 KV cache 可以共同驻留。

这只解决“装得下”，不自动保证量化后的任务质量。量化 checkpoint 的校准数据、
精度声明和限制应查看模型卡，并用自己的冻结评测集复核。

## 3. Blackwell 上必须统一 runtime 与 JIT 工具链

SGLang/FlashInfer 会在首次请求时为 SM120 编译内核。已验证环境中，PyTorch 使用
CUDA 13.0 runtime，但 Ubuntu 系统原有 `nvcc`/`libcudart` 可能属于 CUDA 11。
如果 JIT 链接器找到错误的系统库，编译可以表面成功，运行时却会报
`CUDA error: invalid resource handle`。

本仓库做了三层约束：

1. 锁定 CUDA 13.0 的 NVCC、CRT、NVVM 与 CCCL Python 包；
2. 显式设置 `CUDA_HOME`、`PATH` 和 `LD_LIBRARY_PATH`；
3. 检查已有 JIT `.so` 的 ELF 依赖，把链接到 `libcudart.so.11.0` 的旧缓存移动到
   可恢复备份目录，而不是继续复用或直接删除。

## 4. SM120 FP8 BMM 后端修复

固定 SGLang commit 的 ModelOpt per-tensor FP8 BMM 默认硬编码 cuBLAS。RTX 5090
上真实 Qwen3.8 张量形状触发了 `CUBLAS_STATUS_NOT_SUPPORTED`。提交内置的小补丁
仅在 `_is_sm120_supported` 时把 backend 选为 CUTLASS，其他架构仍使用 cuBLAS。

补丁是 commit-specific 的：`apply_sglang_patches.sh` 先 dry-run，源码不匹配时
立即失败，避免静默把旧补丁套到新的上游代码。

## 5. 先保守基线，再逐项优化

基线配置为：

- `max-running-requests=1`；
- `context-length=65536`；
- `kv-cache-dtype=fp8_e4m3`；
- `mem-fraction-static=0.86`；
- `chunked-prefill-size=2048`；
- 关闭 prefill CUDA Graph，只保留 batch=1 decode graph；
- Mamba cache 使用 `extra_buffer_lazy`，容量 4；
- 首次 JIT `MAX_JOBS=2`；
- 不启用 MTP/DSpark/DFlash 推测解码。

这样可以把“服务能否正确运行”和“优化是否改变输出或内存行为”分开。未来启用
推测解码、提高并发、扩上下文或调高显存比例时，应一次只改一组变量，并重新跑
接口验收、长上下文测试、显存峰值与业务冻结评测。

## 6. 三种不同的通过

1. **环境通过**：固定依赖、CUDA runtime、SGLang commit 和模型哈希一致；
2. **接口通过**：模型列表、对话、工具调用、JSON Schema 输出均满足协议；
3. **业务通过**：在你的独立评测集上，任务准确率、安全性和量化质量达到门槛。

本仓库只给出前两类的复现手段与一次实测记录。第三类必须由使用者自行验证。
