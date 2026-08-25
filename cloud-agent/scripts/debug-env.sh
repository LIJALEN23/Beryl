#!/usr/bin/env bash
#
# debug-env.sh — DeerFlow 调试用 web 环境一键启停
#
# 管理两个 server 端依赖 (全部 nohup 后台化, 不占终端):
#   frontend      3000  Next.js dev server
#   nginx         2026  统一入口 (代理 /api/* → 8001, / → 3000)
#
# llama-server (8080) 由用户手动管理, 脚本只做健康检查提示, 不启动/不停止。
# Gateway (8001) 也不在本脚本管理范围内: 由 VSCode F5 调试启动/停止。
#
# 崩溃自清理: start 时会启动一个 watchdog 后台进程, 监视 8001 端口。
# 一旦 Gateway 消失 (正常停止/强制终止/崩溃), watchdog 自动停掉
# frontend + nginx。VSCode 的 postDebugTask 只覆盖正常停止, 兜不住强制
# 终止, 所以崩溃路径完全由 watchdog 负责。
#
# 所有调试期文件系统产物统一收纳在 <repo>/debug-runtime/ 下:
#   debug-runtime/deer-flow-home/    DEER_FLOW_HOME (threads/users/uploads/memory/sandbox 数据)
#   debug-runtime/deer-flow-home/data  SQLite (config.yaml database.sqlite_dir 指向这里)
#   debug-runtime/logs/              nginx/frontend/llama 日志 + pid 文件
#   debug-runtime/client_body_temp/  nginx 临时目录 (-p prefix 解析)
#
# 用法:
#   ./scripts/debug-env.sh start   启动依赖并等待健康
#   ./scripts/debug-env.sh stop    停止依赖 (先停 nginx/frontend, 最后 llama)
#   ./scripts/debug-env.sh status  查看各端口状态
#
# VSCode F5 已通过 tasks.json (debug-env-start / debug-env-stop) 自动调用本脚本,
# 无需手动执行。
#
set -euo pipefail

REPO_ROOT="$(builtin cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1 && pwd -P)"
RUNTIME_DIR="$REPO_ROOT/debug-runtime"
LOGS_DIR="$RUNTIME_DIR/logs"
DEER_FLOW_HOME_DIR="$RUNTIME_DIR/deer-flow-home"

mkdir -p "$LOGS_DIR" "$DEER_FLOW_HOME_DIR/data" \
  "$RUNTIME_DIR/client_body_temp" "$RUNTIME_DIR/proxy_temp" \
  "$RUNTIME_DIR/fastcgi_temp" "$RUNTIME_DIR/uwsgi_temp" "$RUNTIME_DIR/scgi_temp"

LLAMA_BIN="$HOME/code/special/llama.cpp/build/bin/llama-server"
LLAMA_MODEL="/home/damnman/model/Qwen3.5-4B-Q4_K_M.gguf"
LLAMA_ARGS=(-m "$LLAMA_MODEL" -ngl 99 -t 8 -c 131072 -np 1 --flash-attn on \
  --cache-type-k q8_0 --cache-type-v q8_0 --reasoning off \
  --port 8080 --host 127.0.0.1)
WATCHDOG_PID_FILE="$LOGS_DIR/watchdog.pid"

is_listening() { ss -tlnp 2>/dev/null | grep -q ":$1 "; }

wait_port() { "$REPO_ROOT/scripts/wait-for-port.sh" "$1" "${2:-30}" "$3" >/dev/null 2>&1; }

start_llama() {
  # llama-server 由用户手动管理。此处只检查并提示, 不启动。
  if is_listening 8080; then
    echo "[llama] 8080 运行中 (用户手动管理)"
  else
    echo "[llama] 8080 未运行 — 请手动启动 (示例:)"
    echo "  $LLAMA_BIN ${LLAMA_ARGS[*]}"
  fi
  return 0
}

start_frontend() {
  if is_listening 3000; then
    echo "[front] 3000 已在监听, 跳过"
    return 0
  fi
  if [ ! -d "$REPO_ROOT/frontend/node_modules" ]; then
    echo "[front] frontend/node_modules 缺失 — 先跑 ./scripts/install-frontend-deps.sh"
    exit 1
  fi
  # setsid: 创建新会话, 彻底脱离 VSCode 任务终端的进程组。否则 preLaunchTask
  # 结束/重试时终端向进程组发 SIGHUP, next dev 直接退出 (exit 129)。
  # nohup 只防 SIGHUP 但挡不住进程组信号, setsid 是真正的解法。
  (cd "$REPO_ROOT/frontend" && setsid nohup env PORT=3000 python3 "$REPO_ROOT/scripts/pnpm.py" run dev \
    < /dev/null > "$LOGS_DIR/frontend.log" 2>&1 & echo $! > "$LOGS_DIR/frontend.pid")
  echo "[front] 启动中 pid $(cat "$LOGS_DIR/frontend.pid") (日志: $LOGS_DIR/frontend.log)"
  wait_port 3000 60 frontend || { echo "[front] 启动超时, 看 $LOGS_DIR/frontend.log"; exit 1; }
  echo "[front] OK http://localhost:3000"
}

start_nginx() {
  if is_listening 2026; then
    echo "[nginx] 2026 已在监听, 跳过"
    return 0
  fi
  # Fedora 打包的 nginx 编译默认 client_body_temp_path=/var/lib/nginx/tmp,
  # 普通用户不可写, 启动即 emerg。动态生成调试配置: 在 http 块注入相对
  # prefix 的临时目录 (resolve 到 debug-runtime/ 下)。
  sed '/^http {/a\    client_body_temp_path client_body_temp;\n    proxy_temp_path proxy_temp;\n    fastcgi_temp_path fastcgi_temp;\n    uwsgi_temp_path uwsgi_temp;\n    scgi_temp_path scgi_temp;' \
    "$REPO_ROOT/docker/nginx/nginx.local.conf" > "$RUNTIME_DIR/nginx.debug.conf"
  # -p RUNTIME_DIR: nginx 配置里的相对路径 (logs/, temp/, pid) 全部解析到 debug-runtime/
  # setsid: 同上, 脱离 VSCode 任务终端进程组 (nginx 对 SIGHUP 默认 reload 而非退出,
  # 但避免意外 reload 和未来行为变化)。
  nohup setsid nginx -g 'daemon off;' -c "$RUNTIME_DIR/nginx.debug.conf" -p "$RUNTIME_DIR" \
    < /dev/null > "$LOGS_DIR/nginx.log" 2>&1 &
  echo $! > "$LOGS_DIR/nginx.pid"
  echo "[nginx] 启动中 pid $(cat "$LOGS_DIR/nginx.pid") (日志: $LOGS_DIR/nginx.log)"
  wait_port 2026 20 nginx || { echo "[nginx] 启动超时, 看 $LOGS_DIR/nginx.log"; exit 1; }
  echo "[nginx] OK http://localhost:2026"
}

start_watchdog() {
  # 监视 8001: 先等 Gateway 出现过, 再监视其消亡。一旦消失自动清理依赖。
  # 语义: "见过 Gateway 活着 → 之后消失就清理", 避免 F5 还没起 Gateway 时误杀。
  if [ -f "$WATCHDOG_PID_FILE" ] && kill -0 "$(cat "$WATCHDOG_PID_FILE")" 2>/dev/null; then
    echo "[watchdog] 已在运行 pid $(cat "$WATCHDOG_PID_FILE")"
    return 0
  fi
  # setsid: 同上, watchdog 是长驻监视进程, 必须脱离 VSCode 任务终端进程组
  nohup setsid bash -c "
    is_listening() { ss -tlnp 2>/dev/null | grep -q \":\$1 \"; }
    while ! is_listening 8001; do sleep 3; done
    while is_listening 8001; do sleep 3; done
    echo \"[watchdog] Gateway 8001 已消失, 自动清理 frontend + nginx\"
    '$REPO_ROOT/scripts/debug-env.sh' stop-services
  " < /dev/null > "$LOGS_DIR/watchdog.log" 2>&1 &
  echo $! > "$WATCHDOG_PID_FILE"
  echo "[watchdog] 已启动 pid $(cat "$WATCHDOG_PID_FILE") (Gateway 消失后自动清理, 日志: $LOGS_DIR/watchdog.log)"
}

stop_watchdog() {
  if [ -f "$WATCHDOG_PID_FILE" ]; then
    kill "$(cat "$WATCHDOG_PID_FILE")" 2>/dev/null || true
    rm -f "$WATCHDOG_PID_FILE"
    echo "[watchdog] 已停止"
  else
    echo "[watchdog] 未运行"
  fi
}

stop_nginx() {
  if ! is_listening 2026; then
    echo "[nginx] 未运行"
    return 0
  fi
  nginx -c "$REPO_ROOT/docker/nginx/nginx.local.conf" -p "$RUNTIME_DIR" -s quit 2>/dev/null || true
  for _ in $(seq 1 10); do is_listening 2026 || break; sleep 1; done
  if is_listening 2026 && [ -f "$LOGS_DIR/nginx.pid" ]; then
    kill "$(cat "$LOGS_DIR/nginx.pid")" 2>/dev/null || true
  fi
  echo "[nginx] 已停止"
}

stop_frontend() {
  if ! is_listening 3000; then
    echo "[front] 未运行"
    return 0
  fi
  # next-server 会 fork 子进程, 杀 pid 文件 + 端口兜底
  if [ -f "$LOGS_DIR/frontend.pid" ]; then
    kill "$(cat "$LOGS_DIR/frontend.pid")" 2>/dev/null || true
  fi
  for _ in $(seq 1 10); do is_listening 3000 || break; sleep 1; done
  if is_listening 3000; then
    local port_pid
    port_pid="$(ss -tlnp 2>/dev/null | grep ':3000 ' | grep -oP 'pid=\K[0-9]+' | head -1 || true)"
    [ -n "$port_pid" ] && kill "$port_pid" 2>/dev/null || true
  fi
  echo "[front] 已停止"
}

stop_llama() {
  # llama-server 由用户手动管理, 脚本绝不停止它。
  if is_listening 8080; then
    echo "[llama] 8080 运行中 — 用户手动管理, 不停止"
  else
    echo "[llama] 未运行"
  fi
  return 0
}

status() {
  echo "端口状态:"
  for port in 8080 8001 3000 2026; do
    if is_listening "$port"; then
      echo "  :$port 运行中"
    else
      echo "  :$port 未运行"
    fi
  done
  echo "(8001 = Gateway, 由 VSCode F5 控制)"
  if [ -f "$WATCHDOG_PID_FILE" ] && kill -0 "$(cat "$WATCHDOG_PID_FILE")" 2>/dev/null; then
    echo "watchdog: 运行中 pid $(cat "$WATCHDOG_PID_FILE") (监视 Gateway 消亡)"
  else
    echo "watchdog: 未运行"
  fi
  echo "运行时目录: $RUNTIME_DIR"
}

case "${1:-}" in
  start)
    start_llama
    start_frontend
    start_nginx
    start_watchdog
    echo ""
    echo "============================================"
    echo " web 环境就绪: 浏览器打开 http://localhost:2026"
    echo " Gateway 由 VSCode F5 启动 (8001)"
    echo " 运行时数据: $RUNTIME_DIR"
    echo " 崩溃自清理: Gateway 消失后 frontend/nginx 自动停止"
    echo "============================================"
    ;;
  stop)
    stop_watchdog
    stop_nginx
    stop_frontend
    stop_llama
    echo ""
    echo "依赖已停。Gateway 若还在跑, 用 VSCode 停止调试即可。"
    ;;
  stop-services)
    # 供 watchdog 调用: 只停 frontend + nginx, 不碰 llama
    stop_nginx
    stop_frontend
    ;;
  status)
    status
    ;;
  *)
    echo "用法: $0 {start|stop|status}"
    exit 1
    ;;
esac
