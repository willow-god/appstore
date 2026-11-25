#!/bin/bash
# ============================================================
# ds-harness-remote 安装初始化
# ------------------------------------------------------------
# 1Panel 安装应用时会先执行 scripts/init.sh，再执行 docker compose up。
# 镜像以 node(uid/gid 1000) 运行，而 ./data 绑定目录若由 Docker 自动创建
# 会是 root 属主，容器写 /data/state.json 时报：
#   EACCES: permission denied, open '/data/state.json.tmp'
# 这里在容器启动前预创建 data 目录并把属主交给 uid/gid 1000。
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="$APP_DIR/data"

mkdir -p "$DATA_DIR"
chown -R 1000:1000 "$DATA_DIR"

echo "✅ 已准备数据目录: $DATA_DIR (uid/gid 1000)"
