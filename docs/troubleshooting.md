# 故障排查

## `CUDA error: invalid resource handle`

常见原因是旧的 SGLang JIT `.so` 链接到了系统 `libcudart.so.11.0`，而当前
PyTorch stream 来自 CUDA 13。`run_server.sh` 会检查 ELF 依赖并把旧缓存移动到
`$BASE_DIR/cache-backup/`。确认 `CUDA_HOME` 指向 venv 中的 `nvidia/cu13`，不要
让系统 CUDA 11 的库排在 `LD_LIBRARY_PATH` 前面。

## `CUBLAS_STATUS_NOT_SUPPORTED`

本方案实测是 SM120 上 per-tensor FP8 BMM 的 cuBLAS 路径不支持对应张量形状。
检查：

```bash
cat /data/qwen38-sglang/SGLANG_COMMIT
./apply_sglang_patches.sh
```

commit 必须与 README 的固定值一致。若补丁 dry-run 失败，不要强行套用；上游代码
已经漂移，需要重新验证补丁位置和行为。

## FlashInfer 首次编译失败或主机卡死

保持 `MAX_JOBS=2`。实测主机有 64 GiB 内存；内存更小时应关闭其他任务，必要时
增加可监控的 swap，并查看 `logs/server.log`。`MAX_JOBS` 只限制首次 JIT 编译并发，
不改变服务请求并发。

## 编译器/头文件版本不一致

不要单独升级 `nvidia-cuda-nvcc`。运行：

```bash
./verify_environment.sh
/data/qwen38-sglang/venv/bin/python -m pip install --no-deps \
  -r cuda-jit-requirements.txt
```

本方案要求 JIT 编译关键包保持 CUDA 13.0 组合。其他组合需要重新验证。

## 模型哈希不一致

这意味着下载不完整、镜像内容漂移或使用了不同模型 commit。不要用
`sha256sum` 失败后的文件启动。先保留现场：

```bash
mv /data/qwen38-sglang/models/Qwen3.8-27B-NVFP4 \
  /data/qwen38-sglang/models/Qwen3.8-27B-NVFP4-mismatch
mkdir -p /data/qwen38-sglang/models/Qwen3.8-27B-NVFP4
./complete_install.sh
```

确认不再需要旧目录后再由人工清理。

## 服务启动但开发机访问失败

默认端点只监听服务器回环地址。保持服务端配置不变，在开发机建立隧道：

```bash
ssh -N -L 30000:127.0.0.1:30000 gpu-server
```

然后访问 `http://127.0.0.1:30000/v1/models`。不要把 `BIND_HOST` 改为
`0.0.0.0`，除非已经增加鉴权、防火墙和网络访问控制。

## FP8 KV cache scale 警告

实测 SGLang 会提示 FP8 KV cache 没有独立 scale 并采用 1.0。这不是启动失败，
但也不能据此断言量化质量没有下降。应用上线前应在相同 Prompt、采样参数和模型
commit 下对比 BF16 KV 与 FP8 KV 的冻结评测结果。
