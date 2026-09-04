# Third-party notices

This repository does not redistribute SGLang source code or model weights. Its
scripts download the following third-party artifacts:

## SGLang

- Project: <https://github.com/sgl-project/sglang>
- Pinned commit: `1cf2b8c54d81802abc15dcf23a29b9cc687bc01e`
- License: Apache License 2.0

The file `patches/sglang-sm120-fp8-bmm.patch` modifies one backend-selection
line in that pinned source tree. The patched SGLang source remains subject to
SGLang's upstream license and notices.

## RadixArk/Qwen3.8-27B-NVFP4

- Model: <https://huggingface.co/RadixArk/Qwen3.8-27B-NVFP4>
- Pinned commit: `319f741cce68d7914884900c138a1fbb70a42f30`
- License identified by the model card: Apache License 2.0
- Upstream base model: <https://huggingface.co/Qwen/Qwen3.8-27B>

RadixArk identifies this checkpoint as a third-party mixed NVFP4 W4A4
quantization of Qwen3.8-27B produced with NVIDIA Model Optimizer. Review both
the quantized model card and the upstream Qwen model card before use.

## Python packages

`requirements.lock.txt` records the exact package versions observed in the
verified environment. Each package remains subject to its own license. The
lock file is an environment inventory, not a relicensing of those packages.
