#!/bin/bash
# ============================================================
# ds-harness-remote：修正已安装实例的数据目录属主
# ------------------------------------------------------------
# 应用镜像以 node(uid/gid 1000) 运行，而 Compose 的 ./data 绑定目录由
# Docker 以 root 创建，容器首次启动写 /data/state.json 会报：
#   EACCES: permission denied, open '/data/state.json.tmp'
# 本脚本把已安装实例的 data 目录改为 1000:1000，容器下一次自动重启即可恢复。
#
# scripts/mirror.sh 会按文件名顺序自动执行本脚本；也可以单独执行：
#   bash adapters/ds-harness-remote.sh
#   PANEL_ROOT=/opt/1panel bash adapters/ds-harness-remote.sh
#
# 说明：
#   - 只处理 $PANEL_ROOT/apps/ds-harness-remote/*/ 下、compose 里确实引用
#     本应用镜像的安装实例，不碰其他应用
#   - 目录不存在时按 1000:1000 预创建，避免首次启动才失败
#   - 需要 root 权限执行（1Panel 定时任务默认就是 root）
#
# 退出码：0 完成或无需处理；1 有目录修正失败
# ============================================================
set -euo pipefail

APP_KEY="ds-harness-remote"
APP_IMAGE="ds-harness-remote/server"
APP_UID=1000
APP_GID=1000

PANEL_ROOT="${PANEL_ROOT:-/opt/1panel}"
APPS_ROOT="$PANEL_ROOT/apps/$APP_KEY"

[ -d "$APPS_ROOT" ] || exit 0

fixed=0
failed=0
for install_dir in "$APPS_ROOT"/*/; do
    [ -d "$install_dir" ] || continue

    # 只处理确实部署了本应用的实例，避免同名目录误伤
    compose=""
    for candidate in "$install_dir/docker-compose.yml" "$install_dir/docker-compose.yaml"; do
        if [ -f "$candidate" ] && grep -q "$APP_IMAGE" "$candidate"; then
            compose="$candidate"
            break
        fi
    done
    [ -n "$compose" ] || continue

    data_dir="${install_dir%/}/data"
    mkdir -p "$data_dir"

    current="$(stat -c '%u:%g' "$data_dir" 2>/dev/null || true)"
    [ "$current" = "$APP_UID:$APP_GID" ] && continue

    if chown -R "$APP_UID:$APP_GID" "$data_dir" \
        && [ "$(stat -c '%u:%g' "$data_dir" 2>/dev/null || true)" = "$APP_UID:$APP_GID" ]; then
        fixed=$((fixed + 1))
    else
        failed=$((failed + 1))
    fi
done

if [ "$failed" -gt 0 ]; then
    echo "❌ ds-harness-remote：$failed 个数据目录属主修正失败，请用 root 执行"
    exit 1
fi

# 没有变化时保持静默，只在真正修正过时输出一行
if [ "$fixed" -gt 0 ]; then
    echo "✅ ds-harness-remote：已修正 $fixed 个数据目录属主为 $APP_UID:$APP_GID（容器会自动重启恢复）"
fi
exit 0
