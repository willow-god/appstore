#!/bin/bash
# ============================================================
# kettu-relay 安装初始化
# ------------------------------------------------------------
# 1Panel 安装应用时会先执行 scripts/init.sh，再执行 docker compose up。
# 镜像以非特权用户 uid/gid 65532 运行，并且启动时会拒绝属主不是自己的
# 数据目录，以及权限宽于 0700 的密钥文件。./data 若由 Docker 自动创建
# 会是 root 属主、0755 权限，中继会直接拒绝启动。
# 这里在容器启动前预创建 data 目录，并把属主和权限设置正确。
# ============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
DATA_DIR="$APP_DIR/data"

mkdir -p "$DATA_DIR"
chmod 700 "$DATA_DIR"
chown -R 65532:65532 "$DATA_DIR"

echo "✅ 已准备数据目录: $DATA_DIR (uid/gid 65532, 权限 0700)"
