#!/bin/bash
# Apply the Kimi K3 / K3.1 video-input patch to an SGLang source tree.
# Idempotent; the original files are kept in $ROLLBACK_DIR.
# Usage: [SGL_PY=<sglang python dir>] [SGL_PYTHON=<python>] bash scripts/apply_video_patch.sh [patches/<diff>]
# Default diff: patches/kimi_k3_video_0523.diff (official lmsysorg/sglang:v0.5.23, commit 297e54fd).
set -u
SP=${SGL_PY:-/sgl-workspace/sglang/python}; B=${ROLLBACK_DIR:-/root/rollback_video_0523}; mkdir -p $B
DIFF=$(readlink -f "${1:-$(cd "$(dirname "$0")/.." && pwd)/patches/kimi_k3_video_0523.diff}")
PY=${SGL_PYTHON:-$(command -v /opt/sglang/bin/python3 || command -v python3)}
cd $SP || exit 1
FILES="sglang/srt/environ.py sglang/srt/entrypoints/openai/serving_chat.py sglang/srt/models/kimi_k3_vl.py sglang/srt/multimodal/processors/kimi_k3.py"
for f in $FILES; do [ -f $B/$(basename $f).orig ] || cp $f $B/$(basename $f).orig; done
if [ -f sglang/srt/multimodal/processors/kimi_k3_video.py ]; then
  echo "already patched"
else
  patch -p2 -N --dry-run < "$DIFF" >/dev/null 2>&1 && patch -p2 -N < "$DIFF" | tail -6 || { echo PATCH_FAILED; exit 2; }
fi
$PY -m py_compile $FILES sglang/srt/multimodal/processors/kimi_k3_video.py && echo COMPILE_OK
$PY - <<'PY'
from sglang.srt.multimodal.processors.kimi_k3_video import KimiK3VideoConfig, plan_video
from sglang.srt.multimodal.processors.kimi_k3 import KimiK3ImageProcessor
from sglang.srt.environ import envs
cfg = KimiK3VideoConfig.from_media_proc_cfg(
    {"sample_fps": 8.0, "temporal_merge_kernel_size": 4, "in_patch_limit": 65536,
     "in_patch_limit_each_frame": 16384, "in_patch_limit_video": 655360,
     "max_num_frames_each_video": None, "timestamp_mode": "hh:mm:ss.fff",
     "patch_size": 14, "merge_kernel_size": 2, "patch_limit_on_one_side": 512,
     "fixed_output_tokens": None},
    prompt_format=envs.SGLANG_KIMI_K3_VIDEO_PROMPT_FORMAT.get(),
    patch_budget=envs.SGLANG_KIMI_K3_VIDEO_PATCH_BUDGET.get())
p = plan_video(320, 240, 50, 10.0, cfg)   # 5 s / 10 fps / 320x240 clip: Moonshot = 10 chunks, 1158 video tokens
print("import ok; test clip plan:", len(p.chunks), "chunks,", p.num_tokens, "visual tokens,",
      "grid", p.chunks[0].grid_thw(14), "ts", [c.timestamp_text for c in p.chunks[:3]])
PY
