#!/usr/bin/env bash
# build-all.sh — 编译全部11个服务二进制到 teamgramd/bin/
# 用法: .debug/scripts/build-all.sh
set -e

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG="$ROOT/.debug/logs/build.log"
mkdir -p "$ROOT/.debug/logs"

cd "$ROOT"
echo "[$(date '+%H:%M:%S')] 开始编译 11 个服务 ..." | tee "$LOG"

build() {
    local dir="$1" name="$2"
    echo "[$(date '+%H:%M:%S')] build $name ..." | tee -a "$LOG"
    (cd "$ROOT/$dir" && go build -o "$ROOT/teamgramd/bin/$name" .) >> "$LOG" 2>&1
    echo "[$(date '+%H:%M:%S')] $name OK" | tee -a "$LOG"
}

build app/service/idgen/cmd/idgen idgen
build app/service/status/cmd/status status
build app/service/authsession/cmd/authsession authsession
build app/service/dfs/cmd/dfs dfs
build app/service/media/cmd/media media
build app/service/biz/biz/cmd/biz biz
build app/messenger/msg/cmd/msg msg
build app/messenger/sync/cmd/sync sync
build app/bff/bff/cmd/bff bff
build app/interface/session/cmd/session session
build app/interface/gnetway/cmd/gnetway gnetway

echo "[$(date '+%H:%M:%S')] 全部编译完成" | tee -a "$LOG"
ls -la "$ROOT/teamgramd/bin/" | grep -E 'idgen|status|authsession|dfs|media|biz|msg|sync|bff|session|gnetway' | tee -a "$LOG"
