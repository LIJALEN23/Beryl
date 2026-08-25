#!/usr/bin/env bash
# start-all.sh — 启动中间件 + 除被调试服务外的其余 10 个服务（非调试模式）
# 供 VSCode preLaunchTask 调用，参数: 被调试的服务名（如 gnetway），该服务端口留给 dlv
# 设计:
#   - 无 dlv 在跑(全新调试) → 先清理上次残留的服务进程，保证干净起点
#   - 有 dlv 在跑(多会话) → 不清理，只确保依赖在跑
#   - 端口已被占用(服务正在被调试/已运行) → 跳过启动，防端口冲突
# 用法: .debug/scripts/start-all.sh <skip-service>
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BIN="$ROOT/teamgramd/bin"
COMPOSE="$ROOT/docker-compose-env.yaml"
LOG_DIR="$ROOT/.debug/logs"
mkdir -p "$LOG_DIR"

SKIP="${1:-}"

# 服务名 → 端口 (对应 etc/*.yaml 的 ListenOn)
# 注意: sync 是纯 Kafka 消费者（server.go 无 grpcSrv），无监听端口、不注册 etcd，
#       就绪判定 = 进程存活；其余服务用端口判定
declare -A PORTS=(
  [idgen]=20660 [status]=20670 [authsession]=20450 [dfs]=20640 [media]=20650
  [biz]=20020 [msg]=20030 [bff]=20010 [session]=20120 [gnetway]=20110
)
# sync 无端口，单独列
declare -A NO_PORT=( [sync]=1 )
ORDER=(idgen status authsession dfs media biz msg sync bff session gnetway)

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG_DIR/start-all.log"; }

port_open() { (exec 3<>/dev/tcp/127.0.0.1/$1) 2>/dev/null && { exec 3>&-; return 0; } || return 1; }

# 活跃调试会话判定（dap 端口有客户端连接），僵尸 dlv 不算
source "$ROOT/.debug/scripts/lib-dlv.sh"

# 1. 全新调试(无 dlv)时清理残留服务，保证干净起点
if dlv_active; then
    log "检测到活跃调试会话(dlv)，跳过残留清理"
else
    log "无活跃调试会话，清理残留服务进程 ..."
    for svc in "${ORDER[@]}"; do
        pkill -x "$svc" 2>/dev/null
    done
    # pkill 是异步的，等进程退出+端口释放，否则后续"已在监听"误判
    log "等待残留服务退出 ..."
    deadline=$((SECONDS + 30))
    while [ $SECONDS -lt $deadline ]; do
        alive=0
        for svc in "${ORDER[@]}"; do
            if pgrep -x "$svc" >/dev/null 2>&1; then alive=1; break; fi
        done
        [ "$alive" -eq 0 ] && break
        sleep 1
    done
fi

# 2. 中间件栈 (幂等)
log "确保中间件栈运行 ..."
bash "$ROOT/.debug/scripts/ensure-env.sh" || exit 1

# 3. 按顺序启动除 SKIP 外的服务
for svc in "${ORDER[@]}"; do
    if [ "$svc" = "$SKIP" ]; then
        # 被调试服务: 若已有普通模式实例占用端口，杀掉腾给 dlv（dlv 调试实例的父进程是 dlv，不杀）
        if [ -n "${PORTS[$svc]:-}" ] && port_open "${PORTS[$svc]}"; then
            pid=$(ss -tlnp 2>/dev/null | grep "127.0.0.1:${PORTS[$svc]} " | grep -oP 'pid=\K[0-9]+' | head -1)
            if [ -n "$pid" ]; then
                ppid=$(awk '{print $4}' "/proc/$pid/stat" 2>/dev/null)
                if ! pgrep -x dlv >/dev/null 2>&1 || ! pgrep -x dlv | grep -q "^$ppid$"; then
                    kill "$pid" 2>/dev/null
                    log "停止 $svc 普通实例(pid $pid)，端口 ${PORTS[$svc]} 留给 dlv"
                    # 等端口释放（kill 异步）
                    wdeadline=$((SECONDS + 15))
                    while port_open "${PORTS[$svc]}" && [ $SECONDS -lt $wdeadline ]; do
                        sleep 1
                    done
                else
                    log "$svc 已被 dlv 调试中，跳过"
                fi
            fi
        fi
        continue
    fi
    if [ -n "${PORTS[$svc]:-}" ] && port_open "${PORTS[$svc]}"; then
        log "$svc 端口 ${PORTS[$svc]} 已在监听，跳过启动"
        continue
    fi
    if [ -n "${NO_PORT[$svc]:-}" ] && pgrep -x "$svc" >/dev/null 2>&1; then
        log "$svc 已在运行，跳过启动"
        continue
    fi
    if [ ! -x "$BIN/$svc" ]; then
        log "ERROR: $BIN/$svc 不存在，先编译: .debug/scripts/build-all.sh"
        exit 1
    fi
    (cd "$BIN" && nohup "./$svc" -f="../etc/$svc.yaml" >> "$LOG_DIR/$svc.log" 2>&1 &)
    log "启动 $svc (pid 写入 $LOG_DIR/$svc.log)"
    sleep 1
    # bff 启动后需等待 etcd 注册稳定（参考 runall2.sh）
    [ "$svc" = "bff" ] && sleep 5
done

# 4. 等待除 SKIP 外所有服务就绪（sync 无端口，判进程存活）
log "等待服务就绪 ..."
deadline=$((SECONDS + 90))
for svc in "${ORDER[@]}"; do
    [ "$svc" = "$SKIP" ] && continue
    if [ -n "${NO_PORT[$svc]:-}" ]; then
        while ! pgrep -x "$svc" >/dev/null 2>&1; do
            if [ $SECONDS -ge $deadline ]; then
                log "ERROR: $svc 进程 90s 未存活，查看 $LOG_DIR/$svc.log"
                exit 1
            fi
            sleep 2
        done
        log "$svc 就绪 (进程存活)"
    else
        while ! port_open "${PORTS[$svc]}"; do
            if [ $SECONDS -ge $deadline ]; then
                log "ERROR: $svc 端口 ${PORTS[$svc]} 90s 未就绪，查看 $LOG_DIR/$svc.log"
                exit 1
            fi
            sleep 2
        done
        log "$svc 就绪 (端口 ${PORTS[$svc]})"
    fi
done

log "全部依赖服务就绪 (跳过: $SKIP)"
exit 0
