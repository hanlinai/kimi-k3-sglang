#!/bin/bash
# Apply engy-sglang-fixes.diff (OpenAI-API request handling fixes for Kimi K3.1)
# to an SGLang source tree. Run against the directory that contains python/sglang.
# Usage: SGL_ROOT=<sglang repo root> bash scripts/apply_fixes.sh
set -eu
ROOT=${SGL_ROOT:?set SGL_ROOT to the sglang repository root (the dir containing python/)}
DIFF=$(cd "$(dirname "$0")/.." && pwd)/patches/engy-sglang-fixes.diff
cd "$ROOT"
if patch -p1 -N --dry-run < "$DIFF" >/dev/null 2>&1; then
  patch -p1 -N < "$DIFF"
  echo "applied"
elif patch -p1 -R --dry-run < "$DIFF" >/dev/null 2>&1; then
  echo "already applied"
else
  echo "PATCH_FAILED: the target files have drifted; apply the hunks by hand" >&2; exit 2
fi
