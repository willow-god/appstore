#!/bin/bash
# ============================================================
# Headscale 安装初始化
# ------------------------------------------------------------
# 1Panel 安装应用时会先执行 scripts/init.sh，再执行 docker compose up。
# SQLite 数据库、Noise 私钥和 DERP 私钥都保存在 ./data 中，这里在容器
# 启动前预创建目录并收紧权限，避免 Docker 自动创建成 0755。
# 镜像默认以 root 运行，因此不需要像非 root 镜像那样 chown。
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="$APP_DIR/data"

mkdir -p "$DATA_DIR"
chmod 700 "$DATA_DIR"

echo "✅ 已准备 Headscale 数据目录: $DATA_DIR"
