# kimi-k3-sglang

SGLang patches for serving **Kimi K3 / Kimi K3.1 Pro**, as used on the [Engy](https://engy.ai) inference network.

Engy workers must apply both patch sets below. Workers running their own SGLang build (custom kernels, CUDA graphs and so on) must apply them on top of their stack.

| Patch | What it does |
|---|---|
| [`patches/engy-sglang-fixes.diff`](patches/engy-sglang-fixes.diff) | OpenAI-API request handling for Kimi K3.1 |
| [`patches/kimi_k3_video_k31_day0.diff`](patches/kimi_k3_video_k31_day0.diff) | Video input (base64 / URL) for the K3.1 day-0 SGLang tree |
| [`patches/kimi_k3_video_0523.diff`](patches/kimi_k3_video_0523.diff) | The same video input for official `lmsysorg/sglang:v0.5.23` (commit `297e54fd`) |

## 1. Request-handling fixes (`engy-sglang-fixes.diff`)

This patch touches only `python/sglang/srt/entrypoints/openai/protocol.py` and `serving_chat.py`, so it does not conflict with kernel or scheduler changes.

- `tool_choice: "none"` and `tool_choice: "required"` behave as in Moonshot's and OpenAI's APIs.
- `response_format` combined with a forced tool call is accepted, instead of returning 400. The reply is a tool call, so the JSON grammar does not apply.
- An assistant tool call in the history without `function.name` returns a clean **400**, instead of failing inside the chat template.

Apply it from the SGLang repository root:

```bash
SGL_ROOT=/path/to/sglang bash scripts/apply_fixes.sh
# or: cd /path/to/sglang && patch -p1 -N < patches/engy-sglang-fixes.diff
```

To check whether it is already applied, run `patch -p1 -N --dry-run`. It reports "Reversed (or previously applied)" when the patch is in place.

## 2. Video input (`kimi_k3_video_*.diff`)

These patches add `video_url` support to the Kimi K3 / K3.1 multimodal processor. The prompt-token counts match Moonshot's own API exactly: we checked 9 of 9 clips end to end, from 117 to 42,310 tokens.

Request format:

```json
{"type": "video_url", "video_url": {"url": "data:video/mp4;base64,..."}}
```

`http(s)` URLs work too, subject to SGLang's media-URL policy.

Apply the patch from the SGLang `python` directory:

```bash
# official lmsysorg/sglang:v0.5.23
bash scripts/apply_video_patch.sh

# K3.1 day-0 tree
SGL_PY=/path/to/sglang/python SGL_PYTHON=/path/to/python3 \
  bash scripts/apply_video_patch.sh patches/kimi_k3_video_k31_day0.diff
```

The script is idempotent. It backs up the original files to `$ROLLBACK_DIR` (default `/root/rollback_video_0523`), applies the patch, compiles the patched files, and runs a small import check that prints a test-clip plan.

How the video is processed:
- Frames are sampled at up to 8 fps.
- Each frame is resized independently, with a limit of 16,384 patches per frame.
- Frames are grouped into chunks of 4. Each chunk is preceded by its start timestamp in the prompt.
- The 655,360-patch video budget caps the number of frames, not the resolution, so a single video costs at most about 41k visual tokens.

These requests are rejected with **400** before any frame is decoded:
- corrupt videos;
- clips longer than 60 s;
- requests with more than 64k visual tokens in total.

## Engy workers

After patching, make sure your worker:

1. **Advertises video** in its input modalities (`text`, `image`, `video`), so that the gateway routes video requests to it.
2. **Declares the context length it really serves.** The reference K3.1 Pro deployment serves the full 1M tokens (`--context-length 1048576`).

Before taking regular traffic, workers are checked for:
- chat and streaming;
- tool calls (`tool_choice` none / auto / required);
- JSON output;
- image and base64 video input;
- a prompt longer than 300k tokens.

## License

Apache License 2.0, the same as SGLang. See [LICENSE](LICENSE) and [NOTICE](NOTICE).
