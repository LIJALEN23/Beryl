#!/usr/bin/env bash
# stop-env-if-idle.sh — 探测11个Go服务端口，全部无监听才停中间件栈
# 供 VSCode postDebugTask 调用：调试会话结束时自动执行
# 只要还有任何 teamgram 服务在跑，就保留中间件，防止误杀
# 用法: .debug/scripts/stop-env-if-idle.sh
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE="$ROOT/docker-compose-env.yaml"
LOG_DIR="$ROOT/.debug/logs"
LOG="$LOG_DIR/stop-env-if-idle.log"
mkdir -p "$LOG_DIR"

# 11个Go服务的 RPC 监听端口（对应 etc/*.yaml 的 ListenOn）
SERVICE_PORTS=(20660 20670 20450 20640 20650 20020 20030 20420 20010 20120 20110)

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }

# 检查是否还有服务在监听
alive=0
for port in "${SERVICE_PORTS[@]}"; do
    if (exec 3<>/dev/tcp/127.0.0.1/$port) 2>/dev/null; then
        alive=1
        exec 3>&-
        break
    fi
done

if [ "$alive" -eq 1 ]; then
    log "仍有 Go 服务在运行（端口 $port），保留中间件栈"
    exit 0
fi

log "所有 Go 服务已停止，关闭中间件栈 (docker compose down) ..."
docker compose -f "$COMPOSE" down 2>&1 | tee -a "$LOG"
log "中间件栈已关闭（数据保留在 ./data/）"
exit 0
