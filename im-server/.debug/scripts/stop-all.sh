#!/usr/bin/env bash
# stop-all.sh — 调试会话结束时: 无活跃 dlv 才停全部服务 + 中间件
# 供 VSCode postDebugTask 调用
# 设计:
#   - 有其他活跃调试会话(dlv 端口有客户端连接) → 保留一切，防止误杀
#   - 最后一个会话结束(无活跃 dlv) → kill 全部服务 + docker compose down
#   - 僵尸 dlv 兜底: VSCode 关闭调试但 dlv dap 进程残留(忽略 SIGTERM)时，
#     判定为无活跃连接 → 强杀 dlv → 正常全停，保证"调试结束=全部结束"
# 用法: .debug/scripts/stop-all.sh
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE="$ROOT/docker-compose-env.yaml"
LOG_DIR="$ROOT/.debug/logs"
mkdir -p "$LOG_DIR"

# shellcheck source=lib-dlv.sh
source "$ROOT/.debug/scripts/lib-dlv.sh"

ORDER=(idgen status authsession dfs media biz msg sync bff session gnetway)
log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_DIR/stop-all.log"; }

# 给 dlv 一点退出时间
sleep 2

if dlv_active; then
    log "仍有活跃调试会话(dlv 端口有连接)，保留服务和中间件 [dlv=$(dlv_count)]"
    exit 0
fi

# 无活跃会话: 清理僵尸 dlv（若有），然后全停
if [ "$(dlv_count)" -gt 0 ]; then
    log "检测到僵尸 dlv 进程(无客户端连接)，强杀清理 [dlv=$(dlv_count)]"
    dlv_kill_all
fi

log "无调试会话，停止全部服务 ..."
for svc in "${ORDER[@]}"; do
    pkill -x "$svc" 2>/dev/null && log "停止 $svc"
done
# 兜底: dlv 调试残留的孤儿 __debug_bin 进程（进程名不是服务名，pkill -x 匹配不到）
if pgrep -f "__debug_bin" >/dev/null 2>&1; then
    log "清理调试残留的 __debug_bin 进程"
    pkill -9 -f "__debug_bin" 2>/dev/null
fi

# 等所有服务进程退出 + 端口释放（pkill 是 SIGTERM 异步，立即查端口会误判"服务还在运行"导致中间件不关）
log "等待服务端口释放 ..."
deadline=$((SECONDS + 30))
while [ $SECONDS -lt $deadline ]; do
    alive=0
    for svc in "${ORDER[@]}"; do
        if pgrep -x "$svc" >/dev/null 2>&1; then alive=1; break; fi
    done
    # sync 无端口但进程可能残留，pgrep 已覆盖；__debug_bin 兜底
    if pgrep -f "__debug_bin" >/dev/null 2>&1; then alive=1; fi
    [ "$alive" -eq 0 ] && break
    sleep 1
done
log "服务进程已全部退出"

log "停止中间件栈 ..."
bash "$ROOT/.debug/scripts/stop-env-if-idle.sh"

log "全部已停止"
exit 0
