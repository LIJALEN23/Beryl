#!/usr/bin/env bash
#
# install-frontend-deps.sh — 一次性安装 frontend 依赖 (pnpm install)
# 用法: ./scripts/install-frontend-deps.sh
# 特点: nohup 后台化 + 日志落盘, 不占终端 (交互式 spinner 会抢 TTY)
# 看进度: tail -f logs/frontend-install.log
set -euo pipefail

REPO_ROOT="$(builtin cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd -P)"
cd "$REPO_ROOT/frontend"
mkdir -p "$REPO_ROOT/debug-runtime/logs"

export ELECTRON_SKIP_BINARY_DOWNLOAD=1 PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1

nohup python3 "$REPO_ROOT/scripts/pnpm.py" install \
  --fetch-timeout=30000 --fetch-retries=5 \
  > "$REPO_ROOT/debug-runtime/logs/frontend-install.log" 2>&1 &

echo "pnpm install 已后台启动 (pid $!)"
echo "日志: $REPO_ROOT/debug-runtime/logs/frontend-install.log"
echo "看进度: tail -f $REPO_ROOT/debug-runtime/logs/frontend-install.log"
