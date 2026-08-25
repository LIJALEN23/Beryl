#!/usr/bin/env bash
# ensure-env.sh — 幂等启动中间件栈（全部14个服务），等待核心端口健康后返回
# 供 VSCode preLaunchTask 调用：F5 任意服务前自动执行
# 用法: .debug/scripts/ensure-env.sh
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
COMPOSE="$ROOT/docker-compose-env.yaml"
LOG_DIR="$ROOT/.debug/logs"
LOG="$LOG_DIR/ensure-env.log"
mkdir -p "$LOG_DIR"

# 核心依赖端口（etcd/mysql/redis/kafka/minio），全部健康才算就绪
CORE_PORTS=(2379 3306 6379 9092 9000)

log() { echo "[$(date '+%H:%M:%S')] $*" | tee -a "$LOG"; }

# 已在运行则直接返回
if docker compose -f "$COMPOSE" ps --services --filter status=running 2>/dev/null | grep -q etcd; then
    log "中间件栈已在运行，跳过启动"
    exit 0
fi

# 只起调试核心依赖（内存受限机器，14G 全量会 OOM）:
# etcd/mysql/redis/kafka/minio 必需；minio-mc 一次性建桶。
# jaeger/es/kibana/grafana/prometheus 等需要时手动: docker compose up -d <name>
CORE_SERVICES=(etcd mysql redis kafka minio minio-mc)
log "启动核心中间件: ${CORE_SERVICES[*]} (docker compose up -d) ..."
docker compose -f "$COMPOSE" up -d "${CORE_SERVICES[@]}" 2>&1 | tee -a "$LOG"

# 等待核心端口健康，总超时 180s
log "等待核心端口就绪: ${CORE_PORTS[*]}"
deadline=$((SECONDS + 180))
for port in "${CORE_PORTS[@]}"; do
    while ! (exec 3<>/dev/tcp/127.0.0.1/$port) 2>/dev/null; do
        if [ $SECONDS -ge $deadline ]; then
            log "ERROR: 端口 $port 在 180s 内未就绪，中间件启动可能失败"
            docker compose -f "$COMPOSE" ps 2>&1 | tee -a "$LOG"
            exit 1
        fi
        sleep 2
    done
    log "端口 $port 就绪"
    exec 3>&-
done

# mysql 首次启动要跑 47 个初始化 SQL，等它真正可用（端口通不代表初始化完）
# 通过 mysqladmin ping 确认
log "等待 mysql 初始化完成 (首次启动约1-2分钟) ..."
deadline=$((SECONDS + 240))
while ! docker exec mysql mysqladmin ping -uroot -proot --silent 2>/dev/null | grep -q alive; do
    if [ $SECONDS -ge $deadline ]; then
        log "ERROR: mysql 初始化超时"
        exit 1
    fi
    sleep 3
done
log "mysql 初始化完成"

log "中间件栈就绪"
exit 0
