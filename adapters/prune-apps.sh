#!/bin/bash
# ============================================================
# 按 PRUNE_APPS 删除 1Panel 本地应用目录里已下线的应用
# ------------------------------------------------------------
# scripts/mirror.sh 会按文件名顺序执行 adapters/ 下的每个 .sh，本脚本
# 也可以单独执行：
#   bash adapters/prune-apps.sh
#   PRUNE_APPS="旧应用1,旧应用2" bash adapters/prune-apps.sh
#   PRUNE_APPS=... LOCAL_APPS_DIR=/opt/1panel/resource/apps/local bash adapters/prune-apps.sh
#
# 只删除 $LOCAL_APPS_DIR/<应用名> 这份已部署的应用目录，用来清理上游已经
# 下线、但服务器上一直留着的应用（同步脚本只复制、从不删除）。不卸载已安
# 装实例，也不动其他应用。
#
# 删除保护：
#   - 只认 PRUNE_APPS 里明确写出的名字
#   - 该应用仍在仓库 apps/ 里时跳过（下个同步周期又会被复制回来）
#   - 目标是普通目录且含 data.yml，符号链接不删
#   - LOCAL_APPS_DIR 未显式传参时，由脚本位置推导，且上级目录必须叫 local，
#     避免在普通开发检出里误删兄弟目录
#
# 幂等：没有要删的内容时静默通过。
# 退出码：0 完成（含跳过）；非零只有 rm 之外的环境问题
# ============================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRUNE_VAR="PRUNE_APPS"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"

# 1Panel 本地应用目录：优先用显式传入的，其次由 PANEL_ROOT 拼出，
# 都没有时按脚本位置推导（脚本在 <local>/<应用>/ 里）
if [[ -n "${LOCAL_APPS_DIR:-}" ]]; then
    DEPLOYED_DIR_EXPLICIT=1
elif [[ -n "${PANEL_ROOT:-}" ]]; then
    LOCAL_APPS_DIR="$PANEL_ROOT/resource/apps/local"
    DEPLOYED_DIR_EXPLICIT=1
else
    LOCAL_APPS_DIR="$(dirname "$ROOT_DIR")"
    DEPLOYED_DIR_EXPLICIT=0
fi

# ---------- 读取 PRUNE_APPS ----------
prune_raw="${PRUNE_APPS:-}"
if [[ -z "$prune_raw" ]]; then
    if [[ ! -f "$ENV_FILE" ]]; then
        echo "⚠️  未找到 $ENV_FILE，跳过已部署副本清理"
        exit 0
    fi
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        if [[ "$line" =~ ^${PRUNE_VAR}=\"?([^\"]*)\"?$ ]]; then
            prune_raw="${BASH_REMATCH[1]}"
            break
        fi
    done <"$ENV_FILE"
fi

prune_items=()
IFS=',' read -r -a raw_items <<<"$prune_raw"
for item in ${raw_items[@]+"${raw_items[@]}"}; do
    item="${item#"${item%%[![:space:]]*}"}"
    item="${item%"${item##*[![:space:]]}"}"
    item="${item%$'\r'}"
    [[ -z "$item" ]] && continue
    prune_items+=("$item")
done

if [[ "${#prune_items[@]}" -eq 0 ]]; then
    echo "✅ $PRUNE_VAR 为空，无需清理"
    exit 0
fi

# ---------- 删除已部署的本地应用副本 ----------
if [[ $DEPLOYED_DIR_EXPLICIT -eq 0 && "$(basename "$LOCAL_APPS_DIR")" != "local" ]]; then
    # 脚本不在 1Panel 本地应用目录里（比如普通的开发检出），不做任何删除
    echo "ℹ️  $LOCAL_APPS_DIR 不是 1Panel 本地应用目录，跳过已部署副本清理"
    exit 0
fi

deployed_hit=0
for item in "${prune_items[@]}"; do
    target="$LOCAL_APPS_DIR/$item"

    # 目录不在就是已经清理过，保持安静（幂等）
    [[ -e "$target" ]] || continue

    if [[ -d "$ROOT_DIR/apps/$item" ]]; then
        echo "⚠️  应用 $item 仍在本仓库 apps/ 中，跳过删除已部署副本: $target"
        continue
    fi

    if [[ -L "$target" || ! -d "$target" ]]; then
        echo "⚠️  $target 不是普通目录，跳过删除"
        continue
    fi

    if [[ ! -f "$target/data.yml" ]]; then
        echo "⚠️  $target 缺少 data.yml，不是 1Panel 应用目录，跳过删除"
        continue
    fi

    if rm -rf -- "$target"; then
        echo "🗑️  已删除已部署应用: $target"
        deployed_hit=1
    else
        # 删不掉不该阻断整轮同步，留个提示让维护者手动处理
        echo "⚠️  删除失败，请手动清理: $target"
    fi
done

if [[ $deployed_hit -eq 0 ]]; then
    echo "✅ 已部署应用目录无需清理（$PRUNE_VAR 中的应用不在 $LOCAL_APPS_DIR 中）"
fi
