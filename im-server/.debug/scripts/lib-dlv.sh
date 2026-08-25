#!/usr/bin/env bash
# lib-dlv.sh — dlv 活跃/僵尸判定共享函数，被 start-all.sh / stop-all.sh source
#
# 背景: VSCode Go 插件关闭调试会话时，dlv dap 主进程常残留（忽略 SIGTERM），
#       但 dap 监听端口(127.0.0.1:<port>)上的客户端连接已断开。
#       判定活跃 = 该端口存在 ESTABLISHED 连接；无连接 = 僵尸，可强杀。
#
# 用法: source "$ROOT/.debug/scripts/lib-dlv.sh"

# 返回 0 = 存在活跃调试会话(有客户端连接)；1 = 无活跃会话
dlv_active() {
    local pid port
    for pid in $(pgrep -x dlv 2>/dev/null); do
        # 从 cmdline 提取 --listen=127.0.0.1:<port>
        port=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -oP -- '--listen=127\.0\.0\.1:\K[0-9]+' | head -1)
        [ -n "$port" ] || continue
        # 该端口有 ESTABLISHED 连接 = VSCode 客户端还连着 = 活跃调试
        if ss -tn 2>/dev/null | grep -q "127.0.0.1:$port "; then
            return 0
        fi
    done
    return 1
}

# 强杀所有 dlv 进程（含 dap 主进程与 telemetry 子进程；SIGTERM 会被忽略，用 -9）
dlv_kill_all() {
    local pids
    pids=$(pgrep -x dlv 2>/dev/null)
    [ -n "$pids" ] || return 0
    # shellcheck disable=SC2086
    kill -9 $pids 2>/dev/null
    sleep 1
    return 0
}

# 返回 dlv 进程数量（供日志）
dlv_count() {
    pgrep -x dlv 2>/dev/null | wc -l
}
