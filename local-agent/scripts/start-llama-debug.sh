#!/usr/bin/env bash
# 启动本地模型服务器 (llama-server) 供 local-agent 调试使用
# 用法: scripts/start-llama-debug.sh
# 验证: curl -s http://127.0.0.1:8080/v1/models
set -euo pipefail

LLAMA_SERVER="$HOME/code/special/llama.cpp/build/bin/llama-server"
MODEL="$HOME/model/Qwen3.5-4B-Q4_K_M.gguf"

if ! command -v "$LLAMA_SERVER" >/dev/null 2>&1 && [ ! -x "$LLAMA_SERVER" ]; then
  echo "找不到 llama-server: $LLAMA_SERVER" >&2
  exit 1
fi
if [ ! -f "$MODEL" ]; then
  echo "找不到模型: $MODEL" >&2
  exit 1
fi

exec "$LLAMA_SERVER" \
  -m "$MODEL" \
  -ngl 99 -t 8 -c 131072 -np 1 \
  --flash-attn on \
  --cache-type-k q8_0 --cache-type-v q8_0 \
  --reasoning off \
  --port 8080 --host 127.0.0.1
