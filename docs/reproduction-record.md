# 实机复现记录

## 冻结标识

- 执行日期：2026-09-02
- 环境复核日期：2026-09-04
- GPU：NVIDIA GeForce RTX 5090，32,607 MiB
- 驱动：580.105.08
- OS：Ubuntu 22.04.5 LTS
- Python：3.11.5
- SGLang commit：`1cf2b8c54d81802abc15dcf23a29b9cc687bc01e`
- SGLang 源码压缩包 SHA-256：
  `dd3bfb47b24ee2e38d4ce882844fff0bf3207b5fd080a92bb0b803b3018f55e8`
- 模型 commit：`319f741cce68d7914884900c138a1fbb70a42f30`

完整 Python 包版本见根目录 `requirements.lock.txt`，模型文件哈希见
`model.sha256`。

## 服务参数

```text
served-model-name=Qwen3.8-27B
host=127.0.0.1
port=30000
context-length=65536
kv-cache-dtype=fp8_e4m3
mem-fraction-static=0.86
attention-backend=flashinfer
chunked-prefill-size=2048
max-running-requests=1
disable-prefill-cuda-graph=true
cuda-graph-max-bs-decode=1
reasoning-parser=qwen3
tool-call-parser=qwen3_coder
mamba-radix-cache-strategy=extra_buffer_lazy
mamba-ssm-dtype=bfloat16
max-mamba-cache-size=4
MAX_JOBS=2
```

## 观测结果

- `/v1/models` 和普通聊天通过；固定短回答 0.218 秒；
- 工具调用返回标准 `tool_calls`、JSON 参数和 `finish_reason=tool_calls`；
- JSON Schema 约束输出通过；
- 20,019 prompt tokens 输入通过，端到端 2.330 秒，生成 4 tokens；
- SGLang 报告 KV cache 容量 185,018 tokens；
- 全部验收后，`nvidia-smi` 报告 1,829 MiB 空闲显存。

这些数字来自暖机后的单请求验收，不含标准化重复次数、置信区间或并发测试，不能
作为跨机器性能比较结论。

## 尚未宣称通过的项目

- FP8 KV 与 BF16 KV 的业务精度等价性；
- 多并发吞吐与稳定性；
- 65,536 tokens 以上的服务配置；
- 图像和视频输入；
- MTP、DSpark 或 DFlash 推测解码；
- 其他驱动、GPU、OS 或 Python 版本。
